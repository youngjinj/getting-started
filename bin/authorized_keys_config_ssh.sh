#!/bin/bash

mkdir -p ~/.ssh

cat <<EOF > ~/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDLPbTAYDWEnj5yhju+jffN+h54i4Y0mWUR4pjdxqrlN0nY8QqEYEL15nVpD6keSla0lL/xHQuiGlsR2J/jnz60B+O/HfLWaIxdFrf5xYfzb5mbhNFm8+CgR95drNLTWto2dsCBspOMiR0yd/sCdz/zcTrzfV8Fv86UBEhsL+IJm7z8DOp56F3tR3fpqo4Gg4M5mpA0gwewngRwA5C29n3mMSFcPeujaCKQm0Fuhygny3pHruX/hY4uEyRya6BFgkdTfXUGJvrKk5OV/7EOmtc0d6pldjqMgp7UQsaoy8olOOX8VuObXSIQb3ePjHQxFaiucVXwc0GpoLc7LVzYk1m6um0JsJtY+rJhTbncxb7Ve72KdIxqj/gQnsedE2hlZhbgdOtp+MCrMr50A+EDLhcLXhCuZpgqith9CqXu+r+Xy0ojNpC3z5WbzHFkHOHax/JZDt6yhZ2Yj6HXZ/H1wPTnGgB+VEfuRbcl9xZCtojB8jqLziVG1EPHtxsdGM+MWeK7egXeasp2LmXooV15y3E5nR9Ph5v+vE38GieHeCLpzZECuMECO54YegvHeg6Zv8kgUKzEXC3blHZn+VIIU6r8Wpi+c4jg2PgCNGS/6/EfpfwWYFBXNMpKt09fTuhSEXu989nZxSLtxsAaoz5HFm4f43u18r3WQZ0W4Pq8iis1yw== youngjinj@Youngjinj-LT
EOF

chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys