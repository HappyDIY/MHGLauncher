#include <errno.h>
#include <netdb.h>
#include <resolv.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
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
  return strcasecmp(name, "dispatchcnglobal.yuanshen.com") == 0 ||
         strcasecmp(name, "dispatchosglobal.yuanshen.com") == 0;
}

static int mhg_getaddrinfo(const char *name, const char *service,
                           const struct addrinfo *hints, struct addrinfo **result) {
  if (blocked(name)) return EAI_NONAME;
  return getaddrinfo(name, service, hints, result);
}

static struct hostent *mhg_gethostbyname(const char *name) {
  if (blocked(name)) { h_errno = HOST_NOT_FOUND; return NULL; }
  return gethostbyname(name);
}

static struct hostent *mhg_gethostbyname2(const char *name, int family) {
  if (blocked(name)) { h_errno = HOST_NOT_FOUND; return NULL; }
  return gethostbyname2(name, family);
}

static int mhg_res_query(const char *name, int dns_class, int type,
                         unsigned char *answer, int length) {
  if (blocked(name)) { h_errno = HOST_NOT_FOUND; return -1; }
  return res_query(name, dns_class, type, answer, length);
}

#define MHG_INTERPOSE(replacement, replacee) \
  __attribute__((used)) static struct { const void *new_func; const void *old_func; } \
  _mhg_interpose_##replacee __attribute__((section("__DATA,__interpose"))) = \
  { (const void *)(replacement), (const void *)(replacee) }

MHG_INTERPOSE(mhg_getaddrinfo, getaddrinfo);
MHG_INTERPOSE(mhg_gethostbyname, gethostbyname);
MHG_INTERPOSE(mhg_gethostbyname2, gethostbyname2);
MHG_INTERPOSE(mhg_res_query, res_query);
