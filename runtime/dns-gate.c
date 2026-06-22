#include <dlfcn.h>
#include <errno.h>
#include <netdb.h>
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
  typedef int (*function_t)(const char *, const char *, const struct addrinfo *, struct addrinfo **);
  static function_t original = NULL;
  if (blocked(name)) return EAI_NONAME;
  if (original == NULL) original = (function_t)dlsym(RTLD_NEXT, "getaddrinfo");
  return original(name, service, hints, result);
}

static struct hostent *mhg_gethostbyname(const char *name) {
  typedef struct hostent *(*function_t)(const char *);
  static function_t original = NULL;
  if (blocked(name)) { h_errno = HOST_NOT_FOUND; return NULL; }
  if (original == NULL) original = (function_t)dlsym(RTLD_NEXT, "gethostbyname");
  return original(name);
}

static struct hostent *mhg_gethostbyname2(const char *name, int family) {
  typedef struct hostent *(*function_t)(const char *, int);
  static function_t original = NULL;
  if (blocked(name)) { h_errno = HOST_NOT_FOUND; return NULL; }
  if (original == NULL) original = (function_t)dlsym(RTLD_NEXT, "gethostbyname2");
  return original(name, family);
}

#define MHG_INTERPOSE(replacement, replacee) \
  __attribute__((used)) static struct { const void *new_func; const void *old_func; } \
  _mhg_interpose_##replacee __attribute__((section("__DATA,__interpose"))) = \
  { (const void *)(replacement), (const void *)(replacee) }

MHG_INTERPOSE(mhg_getaddrinfo, getaddrinfo);
MHG_INTERPOSE(mhg_gethostbyname, gethostbyname);
MHG_INTERPOSE(mhg_gethostbyname2, gethostbyname2);
