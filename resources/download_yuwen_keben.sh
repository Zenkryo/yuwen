#!/bin/bash

# 下载小学语文课本
# curl -O https://lx-public.oss-cn-beijing.aliyuncs.com/www/lewen/pdf/小学语文课本/语文一年级上册.pdf
# 从一年级到六年级，分上下册, 每个年级有2个pdf文件, 年级为中文

grade_list=(一年级 二年级 三年级 四年级 五年级 六年级)
ce_list=(上册 下册)

for grade in ${grade_list[@]}; do
    for ce in ${ce_list[@]}; do
        curl -O https://lx-public.oss-cn-beijing.aliyuncs.com/www/lewen/pdf/小学语文课本/语文${grade}${ce}.pdf
    done
done
