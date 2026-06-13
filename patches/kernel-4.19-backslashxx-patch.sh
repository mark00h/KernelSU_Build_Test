#!/bin/bash

patch_files=(
    fs/exec.c
    fs/open.c
    fs/stat.c
    kernel/reboot.c
)

for i in "${patch_files[@]}"; do
    if grep -q "ksu" "$i"; then
        echo "Warning: $i contains KernelSU"
        continue
    fi

    case $i in

    fs/exec.c)
        sed -i '/int do_execve(struct filename \*filename,/i\
        #ifdef CONFIG_KSU\
        extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv,\
                            void *envp, int *flags);\
        #endif' fs/exec.c

        sed -i '/int do_execve(struct filename \*filename,/,/return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);/{/return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);/i\
        #ifdef CONFIG_KSU\
            ksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);\
        #endif
        }' fs/exec.c

        sed -i '/static int compat_do_execve(struct filename \*filename,/,/return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);/{/return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);/i\
        #ifdef CONFIG_KSU\
            ksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);\
        #endif
        }' fs/exec.c
        ;;

    fs/open.c)
        sed -i '/SYSCALL_DEFINE3(faccessat, int, dfd, const char __user \*, filename, int, mode)/i\
        #ifdef CONFIG_KSU\
        extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode,\
                            int *flags);\
        #endif' fs/open.c

        sed -i '/SYSCALL_DEFINE3(faccessat, int, dfd, const char __user \*, filename, int, mode)/,/return do_faccessat(dfd, filename, mode);/{/return do_faccessat(dfd, filename, mode);/i\
        #ifdef CONFIG_KSU\
            ksu_handle_faccessat(&dfd, &filename, &mode, NULL);\
        #endif
        }' fs/open.c
        ;;

    fs/stat.c)
        sed -i '/#if !defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_SYS_NEWFSTATAT)/i\
        #ifdef CONFIG_KSU\
        extern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);\
        #endif' fs/stat.c

        sed -i '/SYSCALL_DEFINE4(newfstatat, int, dfd,/,/error = vfs_fstatat(dfd, filename, &stat, flag);/{/error = vfs_fstatat(dfd, filename, &stat, flag);/i\
        #ifdef CONFIG_KSU\
            ksu_handle_stat(&dfd, &filename, &flag);\
        #endif
        }' fs/stat.c

        sed -i '/SYSCALL_DEFINE4(fstatat64, int, dfd,/,/error = vfs_fstatat(dfd, filename, &stat, flag);/{/error = vfs_fstatat(dfd, filename, &stat, flag);/i\
        #ifdef CONFIG_KSU\
            ksu_handle_stat(&dfd, &filename, &flag);\
        #endif
        }' fs/stat.c
        ;;

    kernel/reboot.c)
        sed -i '/DEFINE_MUTEX(system_transition_mutex);/a\
        #ifdef CONFIG_KSU\
        extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\
        #endif' kernel/reboot.c

        sed -i '/SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,/,/int ret = 0;/{/int ret = 0;/a\
        #ifdef CONFIG_KSU\
            ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);\
        #endif
        }' kernel/reboot.c
        ;;

    esac
done
