/*
 * Copyright (C) 2007 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <pwd.h>
#include <spawn.h>
#include <sys/cdefs.h>

#include "sysdeps.h"

#define TRACE_TAG TRACE_SERVICES
#include "adb.h"
#include "file_sync_service.h"

#if ADB_HOST
#ifndef HAVE_WINSOCK
#include <netinet/in.h>
#include <netdb.h>
#include <sys/ioctl.h>
#endif
#else
#include "android_filesystem_config.h"
#include <cutils/android_reboot.h>
#endif

typedef struct stinfo stinfo;

struct stinfo {
    void (*func)(int rfd, int wfd, void* cookie);
    int rfd;
    int wfd;
    void* cookie;
};

void* service_bootstrap_func(void* x)
{
    stinfo* sti = x;
    sti->func(sti->rfd, sti->wfd, sti->cookie);
    free(sti);
    return 0;
}

#if ADB_HOST
ADB_MUTEX_DEFINE(dns_lock);

static void dns_service(int rfd, int wfd, void* cookie)
{
    char* hostname = cookie;
    struct hostent* hp;
    unsigned zero = 0;

    adb_mutex_lock(&dns_lock);
    hp = gethostbyname(hostname);
    free(cookie);
    if(hp == 0) {
        writex(wfd, &zero, 4);
    } else {
        writex(wfd, hp->h_addr, 4);
    }
    adb_mutex_unlock(&dns_lock);
    adb_close(rfd);
    adb_close(wfd);
}
#else
extern int recovery_mode;

static void recover_service(int rfd, int wfd, void* cookie)
{
    unsigned char* buf = malloc(4096);
    unsigned count = (unsigned)cookie;
    int fd;

    if(!buf) {
        adb_close(rfd);
        adb_close(wfd);
        return;
    }

    fd = adb_creat("/tmp/update", 0644);
    if(fd < 0) {
        free(buf);
        adb_close(rfd);
        adb_close(wfd);
        return;
    }

    while(count > 0) {
        unsigned xfer = (count > 4096) ? 4096 : count;
        if(readx(rfd, buf, xfer)) break;
        if(writex(fd, buf, xfer)) break;
        count -= xfer;
    }

    if(count == 0) {
        writex(wfd, "OKAY", 4);
    } else {
        writex(wfd, "FAIL", 4);
    }
    adb_close(fd);
    free(buf);
    adb_close(rfd);
    adb_close(wfd);

    fd = adb_creat("/tmp/update.begin", 0644);
    adb_close(fd);
}

void restart_root_service(int rfd, int wfd, void* cookie)
{
    char buf[100];
    char value[PROPERTY_VALUE_MAX];

    if(getuid() == 0) {
        snprintf(buf, sizeof(buf), "adbd is already running as root\n");
        writex(wfd, buf, strlen(buf));
    } else {
    // property_get("ro.debuggable", value, "");
        if(strcmp(value, "1") != 0) {
            snprintf(buf, sizeof(buf),
                     "adbd cannot run as root in production builds\n");
            writex(wfd, buf, strlen(buf));
            adb_close(rfd);
            adb_close(wfd);
            return;
        }

    // property_set("service.adb.root", "1");
        snprintf(buf, sizeof(buf), "restarting adbd as root\n");
        writex(wfd, buf, strlen(buf));
    }
    adb_close(rfd);
    adb_close(wfd);
}

void restart_tcp_service(int rfd, int wfd, void* cookie)
{
    char buf[100];
    char value[PROPERTY_VALUE_MAX];
    int port = (int)cookie;

    if(port <= 0) {
        snprintf(buf, sizeof(buf), "invalid port\n");
        writex(wfd, buf, strlen(buf));
        adb_close(rfd);
        adb_close(wfd);
        return;
    }

    snprintf(value, sizeof(value), "%d", port);
  // property_set("service.adb.tcp.port", value);
    snprintf(buf, sizeof(buf), "restarting in TCP mode port: %d\n", port);
    writex(wfd, buf, strlen(buf));
    adb_close(rfd);
    adb_close(wfd);
}

void restart_usb_service(int rfd, int wfd, void* cookie)
{
    char buf[100];

  // property_set("service.adb.tcp.port", "0");
    snprintf(buf, sizeof(buf), "restarting in USB mode\n");
    writex(wfd, buf, strlen(buf));
    adb_close(rfd);
    adb_close(wfd);
}

void reboot_service(int rfd, int wfd, void* arg)
{
    char buf[100];
    int ret;

    sync();

  /* Attempt to unmount the SD card first.
     * No need to bother checking for errors.
     */
#if defined(HAVE_FORKEXEC) || defined(HAVE_VFORKEXEC)
    {
        char* external = getenv("EXTERNAL_STORAGE");
#if defined(HAVE_FORKEXEC)
        int pid = fork();
#else
        // uclibc prior to 1.0.56 have no support for posix_spawn with file action
        // So we use vfork/exec instead
        int pid = vfork();
#endif
        if(pid == 0) {
        /* ask vdc to unmount it */
            execl("/system/bin/vdc", "/system/bin/vdc", "volume", "unmount",
                  external, "force", NULL);
#if defined(HAVE_VFORKEXEC)
            _exit(127);
#endif
        } else if(pid > 0) {
        /* wait until vdc succeeds or fails */
            waitpid(pid, &ret, 0);
        }
    }
#endif

    ret = android_reboot(ANDROID_RB_RESTART2, 0, (char*)arg);
    if(ret < 0) {
        snprintf(buf, sizeof(buf), "reboot failed: %s\n", strerror(errno));
        writex(wfd, buf, strlen(buf));
    }
    free(arg);
    adb_close(rfd);
    adb_close(wfd);
}
#endif

#if 0
static void echo_service(int rfd, int wfd, void *cookie)
{
    char buf[4096];
    int r;
    char *p;
    int c;

    for(;;) {
        r = adb_read(rfd, buf, 4096);
        if(r == 0) goto done;
        if(r < 0) {
            if(errno == EINTR) continue;
            else goto done;
        }

        c = r;
        p = buf;
        while(c > 0) {
            r = write(wfd, p, c);
            if(r > 0) {
                c -= r;
                p += r;
                continue;
            }
            if((r < 0) && (errno == EINTR)) continue;
            goto done;
        }
    }
done:
    close(wfd);
    close(rfd);
}
#endif

static int create_service_thread(void (*func)(int, int, void*), void* cookie,
                                 int out_fds[2])
{
    stinfo* sti;
    adb_thread_t t;
    int svc_to_fw[2];
    int fw_to_svc[2];

    if(pipe(svc_to_fw) < 0 || pipe(fw_to_svc) < 0) {
        printf("cannot create service pipes\n");
        return -1;
    }

    close_on_exec(svc_to_fw[0]);
    close_on_exec(svc_to_fw[1]);
    close_on_exec(fw_to_svc[0]);
    close_on_exec(fw_to_svc[1]);

    sti = malloc(sizeof(stinfo));
    if(sti == 0) fatal("cannot allocate stinfo");
    sti->func = func;
    sti->cookie = cookie;
    sti->rfd = fw_to_svc[0];
    sti->wfd = svc_to_fw[1];

    if(adb_thread_create(&t, service_bootstrap_func, sti)) {
        free(sti);
        adb_close(svc_to_fw[0]);
        adb_close(svc_to_fw[1]);
        adb_close(fw_to_svc[0]);
        adb_close(fw_to_svc[1]);
        printf("cannot create service thread\n");
        return -1;
    }

    out_fds[0] = svc_to_fw[0];
    out_fds[1] = fw_to_svc[1];
    D("service thread started, %d:%d %d:%d\n",
      svc_to_fw[0], svc_to_fw[1], fw_to_svc[0], fw_to_svc[1]);
    return 0;
}

#if !ADB_HOST
/*
 * Create a subprocess running the given command.
 *
 * PTY mode (HAVE_FORKEXEC without ADBD_NO_PTY):
 *   Returns a bidirectional PTY master fd connected to the child.
 *   stdin/stdout/stderr are all connected to the PTY.
 *
 * Pipe mode (ADBD_NO_PTY or HAVE_VFORKEXEC):
 *   Child's stdin is closed immediately after spawn (immediate EOF).
 *   Child's stdout/stderr are captured via a single read-only pipe.
 *   Return value is a read-only fd for reading child's output.
 *   Any writes by the caller to this fd go to void.
 *   No /dev/tty or PTY is allocated; the child cannot acquire
 *   a controlling terminal.
 */
static int create_subprocess(const char* cmd, const char* arg0,
                             const char* arg1, pid_t* pid)
{
#ifdef HAVE_WIN32_PROC
    D("create_subprocess(cmd=%s, arg0=%s, arg1=%s)\n", cmd, arg0, arg1);
    fprintf(stderr,
            "error: create_subprocess not implemented on Win32 (%s %s %s)\n", cmd,
            arg0, arg1);
    return -1;
#elif defined(HAVE_VFORKEXEC) || (defined(HAVE_FORKEXEC) && defined(ADBD_NO_PTY))
    /*
     * Pipe mode: no PTY, child's stdin gets EOF immediately.
     * Returns a read-only fd for child's output.
     * uclibc prior to 1.0.56 have no support for posix_spawn with file action,
     * so we use plain fork/vfork instead.
     */
    int pipe_stdin[2], pipe_stdout[2];
    if(pipe(pipe_stdin) < 0) {
        printf("[ pipe failed: %s ]\n", strerror(errno));
        return -1;
    }
    if(pipe(pipe_stdout) < 0) {
        printf("[ pipe failed: %s ]\n", strerror(errno));
        adb_close(pipe_stdin[0]);
        adb_close(pipe_stdin[1]);
        return -1;
    }

#if defined(HAVE_VFORKEXEC)
    *pid = vfork();
#else
    *pid = fork();
#endif
    if(*pid < 0) {
        printf("- fork/vfork failed: %s -\n", strerror(errno));
        adb_close(pipe_stdin[0]);
        adb_close(pipe_stdin[1]);
        adb_close(pipe_stdout[0]);
        adb_close(pipe_stdout[1]);
        return -1;
    }

    if(*pid == 0) {
        adb_close(pipe_stdin[1]);
        adb_close(pipe_stdout[0]);
        dup2(pipe_stdin[0], 0);
        adb_close(pipe_stdin[0]);
        dup2(pipe_stdout[1], 1);
        dup2(pipe_stdout[1], 2);
        adb_close(pipe_stdout[1]);
        execl(cmd, cmd, arg0, arg1, NULL);
        adb_write(STDERR_FILENO, "- exec failed\n", 14);
#if defined(HAVE_VFORKEXEC)
        _exit(127);
#else
        exit(-1);
#endif
    }

    /* parent: close stdin pipe immediately (child gets EOF) */
    adb_close(pipe_stdin[0]);
    adb_close(pipe_stdin[1]);
    adb_close(pipe_stdout[1]);
    /* return read-only fd for child's output */
    return pipe_stdout[0];

#elif defined(HAVE_FORKEXEC)
    char* devname;
    int ptm;

    ptm = unix_open("/dev/ptmx", O_RDWR);  // | O_NOCTTY);
    if(ptm < 0) {
        printf("[ cannot open /dev/ptmx - %s ]\n", strerror(errno));
        return -1;
    }
    fcntl(ptm, F_SETFD, FD_CLOEXEC);

    if(grantpt(ptm) || unlockpt(ptm) || ((devname = (char*)ptsname(ptm)) == 0)) {
        printf("[ trouble with /dev/ptmx - %s ]\n", strerror(errno));
        adb_close(ptm);
        return -1;
    }

    *pid = fork();
    if(*pid < 0) {
        printf("- fork failed: %s -\n", strerror(errno));
        adb_close(ptm);
        return -1;
    }

    if(*pid == 0) {
        int pts;

        setsid();

        pts = unix_open(devname, O_RDWR);
        if(pts < 0) {
            fprintf(stderr, "child failed to open pseudo-term slave: %s\n", devname);
            exit(-1);
        }

        dup2(pts, 0);
        dup2(pts, 1);
        dup2(pts, 2);

        adb_close(pts);
        adb_close(ptm);

    // set OOM adjustment to zero
        char text[64];
        snprintf(text, sizeof text, "/proc/%d/oom_adj", getpid());
        int fd = adb_open(text, O_WRONLY);
        if(fd >= 0) {
            adb_write(fd, "0", 1);
            adb_close(fd);
        } else {
            D("adb: unable to open %s\n", text);
        }
        execl(cmd, cmd, arg0, arg1, NULL);
        fprintf(stderr, "- exec '%s' failed: %s (%d) -\n", cmd, strerror(errno),
                errno);
        exit(-1);
    } else {
    // Don't set child's OOM adjustment to zero.
    // Let the child do it itself, as sometimes the parent starts
    // running before the child has a /proc/pid/oom_adj.
    // """adb: unable to open /proc/644/oom_adj""" seen in some logs.
        return ptm;
    }
#else
#error "HAVE_FORKEXEC or HAVE_VFORKEXEC required"
#endif
}
#endif /* !ABD_HOST */

#if ADB_HOST || ADBD_NON_ANDROID
#define SHELL_COMMAND "/bin/sh"
#else
#define SHELL_COMMAND "/system/bin/sh"
#endif

#if !ADB_HOST
static void subproc_waiter_service(int rfd, int wfd, void* cookie)
{
    pid_t pid = (pid_t)cookie;

    D("entered. fd=%d of pid=%d\n", rfd, pid);
    for(;;) {
        int status;
        pid_t p = waitpid(pid, &status, 0);
        if(p == pid) {
            D("fd=%d, post waitpid(pid=%d) status=%04x\n", rfd, p, status);
            if(WIFSIGNALED(status)) {
                D("*** Killed by signal %d\n", WTERMSIG(status));
                break;
            } else if(!WIFEXITED(status)) {
                D("*** Didn't exit!!. status %d\n", status);
                break;
            } else if(WEXITSTATUS(status) >= 0) {
                D("*** Exit code %d\n", WEXITSTATUS(status));
                break;
            }
        }
    }
    D("shell exited fd=%d of pid=%d err=%d\n", rfd, pid, errno);
    if(SHELL_EXIT_NOTIFY_FD >= 0) {
        int res;
        res = writex(SHELL_EXIT_NOTIFY_FD, &rfd, sizeof(rfd));
        D("notified shell exit via fd=%d for pid=%d res=%d errno=%d\n",
          SHELL_EXIT_NOTIFY_FD, pid, res, errno);
    }
}

static int create_subproc_thread(const char* name)
{
    stinfo* sti;
    adb_thread_t t;
    int ret_fd;
    pid_t pid;
    if(name) {
        ret_fd = create_subprocess(SHELL_COMMAND, "-c", name, &pid);
    } else {
        ret_fd = create_subprocess(SHELL_COMMAND, "-", 0, &pid);
    }
    D("create_subprocess() ret_fd=%d pid=%d\n", ret_fd, pid);

    sti = malloc(sizeof(stinfo));
    if(sti == 0) fatal("cannot allocate stinfo");
    sti->func = subproc_waiter_service;
    sti->cookie = (void*)pid;
    sti->rfd = ret_fd;
    sti->wfd = ret_fd;

    if(adb_thread_create(&t, service_bootstrap_func, sti)) {
        free(sti);
        adb_close(ret_fd);
        printf("cannot create service thread\n");
        return -1;
    }

    D("service thread started, fd=%d pid=%d\n", ret_fd, pid);
    return ret_fd;
}
#endif

int service_to_fd(const char* name, int out_fds[2])
{
    int ret = -1;
    int fds[2];
    int r;

    if(!strncmp(name, "tcp:", 4)) {
        int port = atoi(name + 4);
        name = strchr(name + 4, ':');
        if(name == 0) {
            ret = socket_loopback_client(port, SOCK_STREAM);
            if(ret >= 0) disable_tcp_nagle(ret);
        } else {
#if ADB_HOST
            adb_mutex_lock(&dns_lock);
            ret = socket_network_client(name + 1, port, SOCK_STREAM);
            adb_mutex_unlock(&dns_lock);
#else
            return -1;
#endif
        }
        if(ret >= 0) {
            out_fds[0] = ret;
            out_fds[1] = ret;
            close_on_exec(ret);
        }
        return ret;
    }

#ifndef HAVE_WINSOCK
    if(!strncmp(name, "local:", 6)) {
        ret = socket_local_client(name + 6, ANDROID_SOCKET_NAMESPACE_RESERVED,
                                  SOCK_STREAM);
    } else if(!strncmp(name, "localreserved:", 14)) {
        ret = socket_local_client(name + 14, ANDROID_SOCKET_NAMESPACE_RESERVED,
                                  SOCK_STREAM);
    } else if(!strncmp(name, "localabstract:", 14)) {
        ret = socket_local_client(name + 14, ANDROID_SOCKET_NAMESPACE_ABSTRACT,
                                  SOCK_STREAM);
    } else if(!strncmp(name, "localfilesystem:", 16)) {
        ret = socket_local_client(name + 16, ANDROID_SOCKET_NAMESPACE_FILESYSTEM,
                                  SOCK_STREAM);
    } else
#endif
#if ADB_HOST
        if(!strncmp("dns:", name, 4)) {
        char* n = strdup(name + 4);
        if(n == 0) return -1;
        r = create_service_thread(dns_service, n, fds);
        if(r < 0) return -1;
        out_fds[0] = fds[0];
        out_fds[1] = fds[1];
        return 0;
    } else
#else /* !ADB_HOST */
    if(!strncmp("dev:", name, 4)) {
        ret = unix_open(name + 4, O_RDWR);
    } else if(!strncmp(name, "framebuffer:", 12)) {
        r = create_service_thread(framebuffer_service, 0, fds);
        if(r < 0) return -1;
        out_fds[0] = fds[0];
        out_fds[1] = fds[1];
        return 0;
    } else if(recovery_mode && !strncmp(name, "recover:", 8)) {
        r = create_service_thread(recover_service, (void*)atoi(name + 8), fds);
        if(r < 0) return -1;
        out_fds[0] = fds[0];
        out_fds[1] = fds[1];
        return 0;
#ifndef ADBD_NO_PTY
    } else if(!strncmp(name, "jdwp:", 5)) {
        ret = create_jdwp_connection_fd(atoi(name + 5));
        if(ret >= 0) {
            out_fds[0] = ret;
            out_fds[1] = ret;
        }
        return ret;
#endif
    } else if(!strncmp(name, "log:", 4)) {
        r = create_service_thread(log_service, get_log_file_path(name + 4), fds);
        if(r < 0) return -1;
        out_fds[0] = fds[0];
        out_fds[1] = fds[1];
        return 0;
    } else if(!HOST && !strncmp(name, "shell:", 6)) {
        if(name[6])
            ret = create_subproc_thread(name + 6);
        else
            ret = create_subproc_thread(0);
        if(ret >= 0) {
            out_fds[0] = ret;
            out_fds[1] = ret;
        }
        return ret;
    } else if(!strncmp(name, "sync:", 5)) {
        r = create_service_thread(file_sync_service, NULL, fds);
        if(r < 0) return -1;
        out_fds[0] = fds[0];
        out_fds[1] = fds[1];
        return 0;
    } else if(!strncmp(name, "remount:", 8)) {
        r = create_service_thread(remount_service, NULL, fds);
        if(r < 0) return -1;
        out_fds[0] = fds[0];
        out_fds[1] = fds[1];
        return 0;
    } else if(!strncmp(name, "reboot:", 7)) {
        void* arg = strdup(name + 7);
        if(arg == 0) return -1;
        r = create_service_thread(reboot_service, arg, fds);
        if(r < 0) return -1;
        out_fds[0] = fds[0];
        out_fds[1] = fds[1];
        return 0;
    } else if(!strncmp(name, "backup:", 7)) {
        char* arg = strdup(name + 7);
        if(arg == NULL) return -1;
        return backup_service(BACKUP, arg, out_fds);
    } else if(!strncmp(name, "restore:", 8)) {
        return backup_service(RESTORE, NULL, out_fds);
    } else if(!strncmp(name, "tcpip:", 6)) {
        int port;
        if(sscanf(name + 6, "%d", &port) == 0) {
            port = 0;
        }
        r = create_service_thread(restart_tcp_service, (void*)port, fds);
        if(r < 0) return -1;
        out_fds[0] = fds[0];
        out_fds[1] = fds[1];
        return 0;
    } else if(!strncmp(name, "usb:", 4)) {
        r = create_service_thread(restart_usb_service, NULL, fds);
        if(r < 0) return -1;
        out_fds[0] = fds[0];
        out_fds[1] = fds[1];
        return 0;
    } else
#endif
#if 0
    if(!strncmp(name, "echo:", 5)){
        r = create_service_thread(echo_service, 0, fds);
        if(r < 0) return -1;
        out_fds[0] = fds[0];
        out_fds[1] = fds[1];
        return 0;
    } else
#endif
    {
    }
    if(ret >= 0) {
        out_fds[0] = ret;
        out_fds[1] = ret;
        close_on_exec(ret);
    }
    return ret;
}

#if ADB_HOST
struct state_info {
    transport_type transport;
    char* serial;
    int state;
};

static void wait_for_state(int rfd, int wfd, void* cookie)
{
    struct state_info* sinfo = cookie;
    char* err = "unknown error";

    D("wait_for_state %d\n", sinfo->state);

    atransport* t = acquire_one_transport(sinfo->state, sinfo->transport,
                                          sinfo->serial, &err);
    if(t != 0) {
        writex(wfd, "OKAY", 4);
    } else {
        sendfailmsg(wfd, err);
    }

    if(sinfo->serial) free(sinfo->serial);
    free(sinfo);
    adb_close(wfd);
    adb_close(rfd);
    D("wait_for_state is done\n");
}
#endif

#if ADB_HOST
asocket* host_service_to_socket(const char* name, const char* serial)
{
    if(!strcmp(name, "track-devices")) {
        return create_device_tracker();
    } else if(!strncmp(name, "wait-for-", strlen("wait-for-"))) {
        struct state_info* sinfo = malloc(sizeof(struct state_info));

        if(serial)
            sinfo->serial = strdup(serial);
        else
            sinfo->serial = NULL;

        name += strlen("wait-for-");

        if(!strncmp(name, "local", strlen("local"))) {
            sinfo->transport = kTransportLocal;
            sinfo->state = CS_DEVICE;
        } else if(!strncmp(name, "usb", strlen("usb"))) {
            sinfo->transport = kTransportUsb;
            sinfo->state = CS_DEVICE;
        } else if(!strncmp(name, "any", strlen("any"))) {
            sinfo->transport = kTransportAny;
            sinfo->state = CS_DEVICE;
        } else {
            free(sinfo);
            return NULL;
        }

        int fds[2];
        if(create_service_thread(wait_for_state, sinfo, fds) < 0) return NULL;
        adb_close(fds[1]);
        return create_local_socket(fds[0]);
    }
    return NULL;
}
#endif /* ADB_HOST */
