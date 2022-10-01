---
title: "字符设备驱动"
subtitle: ""
date: 2022-09-29T20:40:55+08:00
draft: true
author: "wlanxww"
authorLink: "https://wlanxww.com"
description: "适用于petalinux的字符设备驱动开发记录"

tags:
- petalinux
- driver
categories:
- 嵌入式系统

resources:
- name: featured-image
  src: featured-image.jpg
- name: featured-image-preview
  src: featured-image-preview.jpg
---

字符设备驱动
<!--more-->

## 创建kernel module
* `petalinux-create -t modules -n caximem --enable`

## 驱动挂载
