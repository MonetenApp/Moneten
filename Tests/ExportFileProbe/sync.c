#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdio.h>

static char folder[PATH_MAX];
static void record(const char *event) {
	const char *path = getenv("MONETEN_EXPORT_SYNC_TRACE");
	if (!path) return;
	int fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0600);
	if (fd < 0) abort();
	if (write(fd, event, strlen(event)) < 0) abort();
	close(fd);
}
static int probe_sync(int fd) {
	char path[PATH_MAX];
	if (fcntl(fd, F_GETPATH, path) == 0) {
		if (strstr(path, "/.moneten-export-")) record("file\n");
		else if (folder[0] && strcmp(path, folder) == 0) record("directory\n");
	}
	return fsync(fd);
}
static int probe_rename(const char *from, const char *to) {
	int result = rename(from, to);
	if (result == 0 && strstr(from, "/.moneten-export-")) {
		strlcpy(folder, to, sizeof(folder));
		char *slash = strrchr(folder, '/');
		if (slash) *slash = '\0';
		record("rename\n");
	}
	return result;
}
__attribute__((used)) static struct { const void *replacement, *original; } hooks[]
__attribute__((section("__DATA,__interpose"))) = {
	{ (const void *)probe_sync, (const void *)fsync },
	{ (const void *)probe_rename, (const void *)rename }
};
