
**ACF libraries for Lua 5.4 & Haserl for standard usage :**

Get package on system via this shell script

 ```css
 #!/bin/sh

 PATH=/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/root/bin
 
# Package for Alpine ACF Lua 5.4
 apk add gcc musl-dev make pkgconfig asciidoc lua5.4 lua5.4-dev lua5.4-libs lua5.4-md5 haserl-lua5.4 git || exit 1
 
# Export config lib lua 5.4
 export PKG_CONFIG_PATH=/usr/lib/pkgconfig
 
# Clone all Lua 5.4 repos

 git clone https://github.com/trinity-labs/acf-core-lua5.4
 git clone https://github.com/trinity-labs/acf-lib-lua5.4
 git clone https://github.com/trinity-labs/lua5.4-subprocess
 
# build Libs
 cd ./acf-lib-lua5.4
 make install
 
# build ACF
 cd ../acf-core-lua5.4
 make install
 
# build Lua Subprocess
 cd ../lua5.4-subprocess 
 make clean
 make install
 
#Done
exit
  ```
  
