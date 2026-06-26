/*
 * Copyright (C) 2011 The Android Open Source Project
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

#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <spawn.h>

#include "sysdeps.h"

#define TRACE_TAG TRACE_ADB
#include "adb.h"

typedef struct {
    pid_t pid;
    int fd;
} backup_harvest_params;

// harvest the child process then close the pipe end
static void* backup_child_waiter(void* args)
{
    int status;
    backup_harvest_params* params = (backup_harvest_params*)args;

    waitpid(params->pid, &status, 0);
    adb_close(params->fd);
    free(params);
    return NULL;
}

/* returns the data pipe passing the backup data here for forwarding */
int backup_service(BackupOperation op, char* args, int out_fds[2])
{
    pid_t pid;
    int up[2], down[2], dummy[2];
    char* operation;
    int child_pipe, parent_fd, dummy_fd;
    int argc;
    char* p;
    char portnum[16];
    char** bu_args;

    if(op == BACKUP) {
        operation = "backup";
    } else {
        operation = "restore";
    }

    D("backup_service(%s, %s)\n", operation, args);

    // up[2]: child → parent  (backup data)
    // down[2]: parent → child (restore data)
    // dummy[2]: discarded direction
    if(pipe(up) < 0 || pipe(down) < 0 || pipe(dummy) < 0) {
        D("can't create backup/restore pipes\n");
        fprintf(stderr, "unable to create backup/restore pipes\n");
        return -1;
    }

    if(op == BACKUP) {
        child_pipe = up[1];
    } else {
        child_pipe = down[0];
    }

    // Build argv array in parent (required for vfork, safe for fork)
    argc = 3;
    for(p = (char*)args; p && *p;) {
        argc++;
        while(*p && *p != ':') p++;
        if(*p == ':') p++;
    }

    snprintf(portnum, sizeof(portnum), "%d", child_pipe);

    bu_args = (char**)malloc((argc + 1) * sizeof(char*));
    if(bu_args == 0) {
        D("can't allocate bu_args\n");
        adb_close(up[0]);
        adb_close(up[1]);
        adb_close(down[0]);
        adb_close(down[1]);
        adb_close(dummy[0]);
        adb_close(dummy[1]);
        return -1;
    }

    argc = 0;
    bu_args[argc++] = "bu";
    bu_args[argc++] = portnum;
    bu_args[argc++] = operation;
    for(p = (char*)args; p && *p;) {
        bu_args[argc++] = p;
        while(*p && *p != ':') p++;
        if(*p == ':') {
            *p = 0;
            p++;
        }
    }
    bu_args[argc] = NULL;

#if defined(HAVE_FORKEXEC)
    pid = fork();
#elif defined(HAVE_VFORKEXEC)
    pid = vfork();
#else
#error "HAVE_FORKEXEC or HAVE_VFORKEXEC required"
#endif
    if(pid < 0) {
        D("unable to fork/vfork for %s\n", operation);
        adb_close(up[0]);
        adb_close(up[1]);
        adb_close(down[0]);
        adb_close(down[1]);
        adb_close(dummy[0]);
        adb_close(dummy[1]);
        free(bu_args);
        return -1;
    }

    if(pid == 0) {
    // child
        if(op == BACKUP) {
            adb_close(up[0]);
            adb_close(down[0]);
            adb_close(down[1]);
            // keep dummy[0] open so parent's writes to dummy[1] block
            // (prevents EPIPE tearing down the connection prematurely)
        } else {
            adb_close(down[1]);
            adb_close(up[0]);
            adb_close(up[1]);
            // keep dummy[1] open so parent's reads from dummy[0] block
            // (prevents EOF tearing down the connection prematurely)
        }
        execvp("/system/bin/bu", bu_args);
        fprintf(stderr, "Unable to exec 'bu', bailing\n");
#if defined(HAVE_VFORKEXEC)
        _exit(127);
#else
        exit(-1);
#endif
    }

    // parent
    D("fork/vfork() returned pid %d\n", pid);
    if(op == BACKUP) {
        parent_fd = up[0];
        dummy_fd = dummy[1];
        adb_close(up[1]);
        adb_close(down[0]);
        adb_close(down[1]);
        // dummy[0] held open by child; parent uses dummy[1]
    } else {
        parent_fd = dummy[0];
        dummy_fd = down[1];
        adb_close(down[0]);
        adb_close(up[0]);
        adb_close(up[1]);
        // dummy[1] held open by child; parent uses dummy[0]
    }
    free(bu_args);

    close_on_exec(parent_fd);
    close_on_exec(dummy_fd);

    backup_harvest_params* params =
        (backup_harvest_params*)malloc(sizeof(backup_harvest_params));
    if(!params) {
        adb_close(parent_fd);
        adb_close(dummy_fd);
        D("Unable to allocate harvester params\n");
        return -1;
    }
    params->pid = pid;
    params->fd = parent_fd;
    adb_thread_t t;
    if(adb_thread_create(&t, backup_child_waiter, params)) {
        adb_close(parent_fd);
        adb_close(dummy_fd);
        free(params);
        D("Unable to create child harvester\n");
        return -1;
    }

    out_fds[0] = parent_fd;
    out_fds[1] = dummy_fd;
    D("Backup service returning (read=%d, write=%d)\n", out_fds[0], out_fds[1]);
    return 0;
}
