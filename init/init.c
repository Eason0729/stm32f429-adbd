#include <fcntl.h>
#include <unistd.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>

#define pivot_root(new_root, put_old) syscall(__NR_pivot_root, new_root, put_old)

int main(void)
{
    int i;
    char *sh_argv[] = {"sh", NULL};
    char *sh_envp[] = {
        "PATH=/run/bin:/bin:/sbin:/usr/bin:/usr/sbin",
        NULL
    };

    for (i = 0; i < 60; i++) {
        if (access("/dev/mmcblk0", F_OK) == 0) {
            if (mount("/dev/mmcblk0", "/mnt", "ext2", 0, NULL) == 0)
                break;
        }
        usleep(500000);
    }

    if (access("/mnt/bin/sh", F_OK) != 0) {
        write(2, "init: SD card /mnt/bin/sh not found\n", 35);
        write(2, "init: halted\n", 13);
        for (;;) pause();
    }

    mount("proc", "/mnt/proc", "proc", 0, NULL);
    mount("sysfs", "/mnt/sys", "sysfs", 0, NULL);
    mount("devtmpfs", "/mnt/dev", "devtmpfs", 0, NULL);
    mount("devpts", "/mnt/dev/pts", "devpts", 0, NULL);
    mount("configfs", "/mnt/sys/kernel/config", "configfs", 0, NULL);

    mount("ramfs", "/mnt/var", "ramfs", 0, NULL);

    pivot_root("/mnt", "/mnt/oldroot");
    chdir("/");

    umount2("/oldroot", MNT_DETACH);

    if (vfork() == 0) {
        char *adbd_argv[] = {"/bin/sh", "/usr/bin/start_adbd.sh", NULL};
        execve("/bin/sh", adbd_argv, sh_envp);
        _exit(1);
    }

    execve("/bin/sh", sh_argv, sh_envp);

    write(2, "init: exec /bin/sh failed\n", 25);
    for (;;) pause();
    return 1;
}
