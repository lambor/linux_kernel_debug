linux_source_path:=/home/dcnh/MyGithub/linux

obj-m := hello.o

all: hello.c
	$(MAKE) -C $(linux_source_path) M=$(PWD) modules

clean:
	rm -rf *.o *.ko *.order *.symvers *.mod.c