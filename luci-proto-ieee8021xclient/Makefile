#
# Copyright (C) 2021 David Yang <mmyangfl@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for wired IEEE 802.1X client
LUCI_DESCRIPTION:=Adds the "IEEE 802.1X Client" protocol to the interface
	settings of LuCI. Requires the ieee8021xclient package.
LUCI_DEPENDS:=+ieee8021xclient
LUCI_PKGARCH:=all

PKG_NAME:=luci-proto-ieee8021xclient
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-or-later
PKG_MAINTAINER:=David Yang <mmyangfl@gmail.com>

include $(TOPDIR)/feeds/luci/luci.mk
