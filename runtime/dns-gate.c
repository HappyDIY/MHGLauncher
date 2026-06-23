#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <resolv.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>

static int gate_active(void) {
  const char *path = getenv("MHG_DNS_GATE_FILE");
  const char *owner = getenv("MHG_DNS_GATE_OWNER_PID");
  if (path == NULL || owner == NULL || access(path, F_OK) != 0) return 0;
  char *end = NULL;
  long pid = strtol(owner, &end, 10);
  return end != owner && *end == '\0' && pid > 1 && (kill((pid_t)pid, 0) == 0 || errno == EPERM);
}

static int blocked(const char *name) {
  if (name == NULL || !gate_active()) return 0;
  int matches = strcasecmp(name, "dispatchcnglobal.yuanshen.com") == 0 ||
                strcasecmp(name, "dispatchosglobal.yuanshen.com") == 0;
  if (matches) unlink(getenv("MHG_DNS_GATE_FILE"));
  return matches;
}

static void *original(const char *name) {
  return dlsym(RTLD_NEXT, name);
}

static void log_query(const char *api, const char *name, int denied, int result, const char *address) {
  const char *path = getenv("MHG_DNS_LOG_FILE");
  if (path == NULL || name == NULL) return;
  char host[512];
  size_t index = 0;
  for (; name[index] != '\0' && index < sizeof(host) - 1; index++) {
    char value = name[index];
    host[index] = value == '\t' || value == '\n' || value == '\r' ? '?' : value;
  }
  host[index] = '\0';
  struct timeval time;
  gettimeofday(&time, NULL);
  char line[768];
  int length = snprintf(line, sizeof(line), "%lld\t%d\t%s\t%s\t%s\t%d\t%s\n",
                        (long long)time.tv_sec * 1000 + time.tv_usec / 1000,
                        getpid(), api, host, denied ? "blocked" : "allowed", result,
                        address == NULL ? "" : address);
  if (length <= 0) return;
  int descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT, 0600);
  if (descriptor < 0) return;
  write(descriptor, line, (size_t)length);
  close(descriptor);
}

static int mhg_getaddrinfo(const char *name, const char *service,
                           const struct addrinfo *hints, struct addrinfo **result) {
  int denied = blocked(name);
  const char *api = hints != NULL && hints->ai_family == AF_INET6 ? "getaddrinfo/AAAA" :
                    hints != NULL && hints->ai_family == AF_INET ? "getaddrinfo/A" : "getaddrinfo/ANY";
  if (denied) { log_query(api, name, 1, EAI_NONAME, NULL); return EAI_NONAME; }
  int (*resolve)(const char *, const char *, const struct addrinfo *, struct addrinfo **) = original("getaddrinfo");
  int code = resolve == NULL ? EAI_FAIL : resolve(name, service, hints, result);
  char address[NI_MAXHOST] = "";
  if (code == 0 && result != NULL && *result != NULL) {
    getnameinfo((*result)->ai_addr, (*result)->ai_addrlen, address, sizeof(address), NULL, 0, NI_NUMERICHOST);
  }
  log_query(api, name, 0, code, address);
  return code;
}

static struct hostent *mhg_gethostbyname(const char *name) {
  int denied = blocked(name);
  if (denied) { h_errno = HOST_NOT_FOUND; log_query("gethostbyname", name, 1, h_errno, NULL); return NULL; }
  struct hostent *(*resolve)(const char *) = original("gethostbyname");
  struct hostent *result = resolve == NULL ? NULL : resolve(name);
  char address[INET6_ADDRSTRLEN] = "";
  if (result != NULL && result->h_addr_list[0] != NULL) inet_ntop(result->h_addrtype, result->h_addr_list[0], address, sizeof(address));
  log_query("gethostbyname", name, 0, result == NULL ? h_errno : 0, address);
  return result;
}

static struct hostent *mhg_gethostbyname2(const char *name, int family) {
  int denied = blocked(name);
  if (denied) { h_errno = HOST_NOT_FOUND; log_query("gethostbyname2", name, 1, h_errno, NULL); return NULL; }
  struct hostent *(*resolve)(const char *, int) = original("gethostbyname2");
  struct hostent *result = resolve == NULL ? NULL : resolve(name, family);
  char address[INET6_ADDRSTRLEN] = "";
  if (result != NULL && result->h_addr_list[0] != NULL) inet_ntop(result->h_addrtype, result->h_addr_list[0], address, sizeof(address));
  log_query("gethostbyname2", name, 0, result == NULL ? h_errno : 0, address);
  return result;
}

static int mhg_res_query(const char *name, int dns_class, int type,
                         unsigned char *answer, int length) {
  int denied = blocked(name);
  if (denied) { h_errno = HOST_NOT_FOUND; log_query("res_query", name, 1, h_errno, NULL); return -1; }
  int (*resolve)(const char *, int, int, unsigned char *, int) = original("res_query");
  int result = resolve == NULL ? -1 : resolve(name, dns_class, type, answer, length);
  log_query(type == ns_t_aaaa ? "res_query/AAAA" : type == ns_t_a ? "res_query/A" : "res_query", name,
            0, result < 0 ? h_errno : 0, NULL);
  return result;
}

#define MHG_INTERPOSE(replacement, replacee) \
  __attribute__((used)) static struct { const void *new_func; const void *old_func; } \
  _mhg_interpose_##replacee __attribute__((section("__DATA,__interpose"))) = \
  { (const void *)(replacement), (const void *)(replacee) }

MHG_INTERPOSE(mhg_getaddrinfo, getaddrinfo);
MHG_INTERPOSE(mhg_gethostbyname, gethostbyname);
MHG_INTERPOSE(mhg_gethostbyname2, gethostbyname2);
MHG_INTERPOSE(mhg_res_query, res_query);
