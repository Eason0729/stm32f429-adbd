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
#include <fcntl.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <spawn.h>

#include "fdevent.h"
#include "adb.h"

#include <cutils/fs.h>
#include <linux/fb.h>
#include <sys/ioctl.h>
#include <sys/mman.h>

/* TODO:
** - sync with vsync to avoid tearing
*/
/* This version number defines the format of the fbinfo struct.
   It must match versioning in ddms where this data is consumed. */
#define DDMS_RAWIMAGE_VERSION 1
struct fbinfo {
    unsigned int version;
    unsigned int bpp;
    unsigned int size;
    unsigned int width;
    unsigned int height;
    unsigned int red_offset;
    unsigned int red_length;
    unsigned int blue_offset;
    unsigned int blue_length;
    unsigned int green_offset;
    unsigned int green_length;
    unsigned int alpha_offset;
    unsigned int alpha_length;
} __attribute__((packed));

void framebuffer_service(int rfd, int wfd, void* cookie)
{
    struct fbinfo fbinfo;
    unsigned int i;
    char* buf = malloc(640);
    int fd_screencap;
    int w, h, f;
    int fds[2];

    if(!buf) goto done;

    if(pipe(fds) < 0) goto done;

    pid_t pid = 0;
#if defined(HAVE_FORKEXEC)
    pid = fork();
#elif defined(HAVE_VFORKEXEC)
    // uclibc prior to 1.0.56 have no support for posix_spawn with file action
    // So we use vfork/exec instead
    pid = vfork();
#else
#error "HAVE_FORKEXEC or HAVE_VFORKEXEC required"
#endif
    if(pid < 0) goto done;
    if(pid == 0) {
        dup2(fds[1], STDOUT_FILENO);
        close(fds[0]);
        close(fds[1]);
        execvp("screencap", (char*[]){"screencap", NULL});
#if defined(HAVE_VFORKEXEC)
        _exit(1);
#else
        exit(1);
#endif
    }

    fd_screencap = fds[0];

  /* read w, h & format */
    if(readx(fd_screencap, &w, 4)) goto done;
    if(readx(fd_screencap, &h, 4)) goto done;
    if(readx(fd_screencap, &f, 4)) goto done;

    fbinfo.version = DDMS_RAWIMAGE_VERSION;
  /* see hardware/hardware.h */
    switch(f) {
    case 1: /* RGBA_8888 */
        fbinfo.bpp = 32;
        fbinfo.size = w * h * 4;
        fbinfo.width = w;
        fbinfo.height = h;
        fbinfo.red_offset = 0;
        fbinfo.red_length = 8;
        fbinfo.green_offset = 8;
        fbinfo.green_length = 8;
        fbinfo.blue_offset = 16;
        fbinfo.blue_length = 8;
        fbinfo.alpha_offset = 24;
        fbinfo.alpha_length = 8;
        break;
    case 2: /* RGBX_8888 */
        fbinfo.bpp = 32;
        fbinfo.size = w * h * 4;
        fbinfo.width = w;
        fbinfo.height = h;
        fbinfo.red_offset = 0;
        fbinfo.red_length = 8;
        fbinfo.green_offset = 8;
        fbinfo.green_length = 8;
        fbinfo.blue_offset = 16;
        fbinfo.blue_length = 8;
        fbinfo.alpha_offset = 24;
        fbinfo.alpha_length = 0;
        break;
    case 3: /* RGB_888 */
        fbinfo.bpp = 24;
        fbinfo.size = w * h * 3;
        fbinfo.width = w;
        fbinfo.height = h;
        fbinfo.red_offset = 0;
        fbinfo.red_length = 8;
        fbinfo.green_offset = 8;
        fbinfo.green_length = 8;
        fbinfo.blue_offset = 16;
        fbinfo.blue_length = 8;
        fbinfo.alpha_offset = 24;
        fbinfo.alpha_length = 0;
        break;
    case 4: /* RGB_565 */
        fbinfo.bpp = 16;
        fbinfo.size = w * h * 2;
        fbinfo.width = w;
        fbinfo.height = h;
        fbinfo.red_offset = 11;
        fbinfo.red_length = 5;
        fbinfo.green_offset = 5;
        fbinfo.green_length = 6;
        fbinfo.blue_offset = 0;
        fbinfo.blue_length = 5;
        fbinfo.alpha_offset = 0;
        fbinfo.alpha_length = 0;
        break;
    case 5: /* BGRA_8888 */
        fbinfo.bpp = 32;
        fbinfo.size = w * h * 4;
        fbinfo.width = w;
        fbinfo.height = h;
        fbinfo.red_offset = 16;
        fbinfo.red_length = 8;
        fbinfo.green_offset = 8;
        fbinfo.green_length = 8;
        fbinfo.blue_offset = 0;
        fbinfo.blue_length = 8;
        fbinfo.alpha_offset = 24;
        fbinfo.alpha_length = 8;
        break;
    default:
        goto done;
    }

  /* write header */
    if(writex(wfd, &fbinfo, sizeof(fbinfo))) goto done;

  /* write data */
    for(i = 0; i < fbinfo.size; i += 640) {
        if(readx(fd_screencap, buf, 640)) goto done;
        if(writex(wfd, buf, 640)) goto done;
    }
    if(readx(fd_screencap, buf, fbinfo.size % 640)) goto done;
    if(writex(wfd, buf, fbinfo.size % 640)) goto done;

done:
    if(pid > 0) TEMP_FAILURE_RETRY(waitpid(pid, NULL, 0));

    free(buf);
    close(fds[0]);
    close(fds[1]);
    close(rfd);
    close(wfd);
}
