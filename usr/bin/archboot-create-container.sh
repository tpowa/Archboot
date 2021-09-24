#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_PWD="$(pwd)"
_BASENAME="$(basename "${0}")"
_CACHEDIR=""$1"/var/cache/pacman/pkg"

usage () {
	echo "${_BASENAME}: usage"
	echo "CREATE ARCHBOOT CONTAINER"
	echo "-----------------------------"
	echo "Usage: ${_BASENAME} <directory>"
	echo "This will create an archboot container for an archboot image."
	exit 0
}

[[ -z "${1}" ]] && usage

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi

# prepare pacman dirs
mkdir -p "$1"/var/lib/pacman
mkdir -p "${_CACHEDIR}"
# install archboot
pacman --root "$1" -Sy base archboot --noconfirm --cachedir "${_PWD}"/"${_CACHEDIR}"
# generate locales
systemd-nspawn -D "$1" /bin/bash -c "echo 'en_US ISO-8859-1' >> /etc/locale.gen"
systemd-nspawn -D "$1" /bin/bash -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen"
systemd-nspawn -D "$1" locale-gen
# generate pacman keyring
systemd-nspawn -D "$1" pacman-key --init
systemd-nspawn -D "$1" pacman-key --populate archlinux
# add genneral mirror
systemd-nspawn -D "$1" /bin/bash -c "echo 'Server = https://mirror.rackspace.com/archlinux/\$repo/os/\$arch' >> /etc/pacman.d/mirrorlist"
# disable checkspace option in pacman.conf, to allow to install packages in environment
systemd-nspawn -D "$1" /bin/bash -c "sed -i -e 's:^CheckSpace:#CheckSpace:g' /etc/pacman.conf"
# enable parallel downloads
systemd-nspawn -D "$1" /bin/bash -c "sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' /etc/pacman.conf"
# reinstall kernel to get files in /boot
systemd-nspawn -D "$1" pacman -Sy linux --noconfirm
# clean cache
systemd-nspawn -D "$1" pacman -Scc --noconfirm
# clean container from not needed files
rm -r "$1"/usr/include
rm -r "$1"/usr/share/{man,doc}
rm -r "$1"/lib/firmware/{atusb,av7110,amdgpu,cadence,cpia2,cypress,dabusb,dpaa2,dsp56k,edgeport,emi26,emi62,ess,go7007,imx,inside-secure,keyspan,keyspan_pda,korg,matrox,meson,microchip,moxa,mwlwifi,myricom,qca,qcom,r128,rockchip,rsi,rtl_bt,rtw89,sb16,silabs,sxg,ti,ti-keystone,ttusb-budget,vicam,vxge,yamaha}
rm "$1"/lib/firmware/{ar7010.fw,ar7010_1_1.fw,ar9170-1.fw,ar9170-2.fw,ar9271.fw,as102_data1_st.hex,as102_data2_st.hex,ath3k-1.fw,atmsar11.fw,bnx2x-e1h-4.8.53.0.fw,bnx2x-e1h-5.2.7.0.fw,bnx2x-e1h-5.2.13.0.fw,bnx2x-e1-4.8.53.0.fw,bnx2x-e1-5.2.7.0.fw,bnx2x-e1-5.2.13.0.fw,cbfw-3.2.1.1.bin,cbfw-3.2.3.0.bin,cmmb_vega_12mhz.inp,cmmb_venice_12mhz.inp,copy-firmware.sh,ct2fw-3.2.1.1.bin,ct2fw-3.2.3.0.bin,ctefx.bin,ctfw-3.2.1.1.bin,ctfw-3.2.3.0.bin,dvb-fe-xc4000-1.4.1.fw,dvb-fe-xc5000c-4.1.30.7.fw,dvb-fe-xc5000-1.6.114.fw,dvb-usb-dib0700-1.20.fw,dvb-usb-it9135-01.fw,dvb-usb-it9135-02.fw,dvb-usb-terratec-h5-drxk.fw,dvb_nova_12mhz.inp,dvb_nova_12mhz_b0.inp,ctspeq.bin,f2255usb.bin,hfi1_dc8051.fw,hfi1_fabric.fw,hfi1_pcie.fw,hfi1_sbus.fw,htc_7010.fw,htc_9271.fw,i2400m-fw-usb-1.4.sbcf,i2400m-fw-usb-1.5.sbcf,i6050-fw-usb-1.5.sbcf,isdbt_nova_12mhz.inp,isdbt_nova_12mhz_b0.inp,isdbt_rio.inp,iwlwifi-1000-3.ucode,iwlwifi-3160-7.ucode,iwlwifi-3160-8.ucode,iwlwifi-3160-9.ucode,iwlwifi-3160-10.ucode,iwlwifi-3160-12.ucode,iwlwifi-3160-13.ucode,iwlwifi-3160-16.ucode,iwlwifi-3160-17.ucode,iwlwifi-3168-21.ucode,iwlwifi-3168-22.ucode,iwlwifi-3168-27.ucode,iwlwifi-5000-1.ucod,iwlwifi-5000-2.ucode,iwlwifi-6000g2a-5.ucode,iwlwifi-6000g2b-5.ucode,iwlwifi-6000-4.ucode,iwlwifi-6050-4.ucode,iwlwifi-7260-7.ucode,iwlwifi-7260-8.ucode,iwlwifi-7260-9.ucode,iwlwifi-7260-10.ucode,iwlwifi-7260-12.ucode,iwlwifi-7260-13.ucode,iwlwifi-7260-16.ucode,iwlwifi-7265D-10.ucode,iwlwifi-7265D-12.ucode,iwlwifi-7265D-13.ucode,iwlwifi-7265D-16.ucode,iwlwifi-7265D-17.ucode,iwlwifi-7265D-21.ucode,iwlwifi-7265D-22.ucode,iwlwifi-7265D-27.ucode,iwlwifi-7265-8.ucode,iwlwifi-7265-9.ucode,iwlwifi-7265-10.ucode,iwlwifi-7265-12.ucode,iwlwifi-7265-13.ucode,iwlwifi-7265-16.ucode,iwlwifi-8000C-13.ucode,iwlwifi-8000C-16.ucode,iwlwifi-8000C-21.ucode,iwlwifi-8000C-22.ucode,iwlwifi-8000C-27.ucode,iwlwifi-8000C-31.ucode,iwlwifi-8000C-34.ucode,iwlwifi-8265-21.ucode,iwlwifi-8265-22.ucode,iwlwifi-8265-27.ucode,iwlwifi-8265-31.ucode,iwlwifi-8265-34.ucode,iwlwifi-9000-pu-b0-jf-b0-33.ucode,iwlwifi-9000-pu-b0-jf-b0-34.ucode,iwlwifi-9000-pu-b0-jf-b0-38.ucode,iwlwifi-9000-pu-b0-jf-b0-41.ucode,iwlwifi-9000-pu-b0-jf-b0-43.ucode,iwlwifi-9260-th-b0-jf-b0-33.ucode,iwlwifi-9260-th-b0-jf-b0-34.ucode,iwlwifi-9260-th-b0-jf-b0-38.ucode,iwlwifi-9260-th-b0-jf-b0-41.ucode,iwlwifi-9260-th-b0-jf-b0-43.ucode,iwlwifi-QuZ-a0-hr-b0-48.ucode,iwlwifi-QuZ-a0-hr-b0-50.ucode,iwlwifi-QuZ-a0-hr-b0-53.ucode,iwlwifi-QuZ-a0-hr-b0-55.ucode,iwlwifi-QuZ-a0-hr-b0-59.ucode,iwlwifi-QuZ-a0-hr-b0-62.ucode,iwlwifi-QuZ-a0-hr-b0-63.ucode,iwlwifi-QuZ-a0-jf-b0-48.ucode,iwlwifi-QuZ-a0-jf-b0-50.ucode,iwlwifi-QuZ-a0-jf-b0-53.ucode,iwlwifi-QuZ-a0-jf-b0-55.ucode,iwlwifi-QuZ-a0-jf-b0-59.ucode,iwlwifi-QuZ-a0-jf-b0-62.ucode,iwlwifi-QuZ-a0-jf-b0-63.ucode,iwlwifi-Qu-b0-hr-b0-48.ucode,iwlwifi-Qu-b0-hr-b0-50.ucode,iwlwifi-Qu-b0-hr-b0-53.ucode,iwlwifi-Qu-b0-hr-b0-55.ucode,iwlwifi-Qu-b0-hr-b0-59.ucode,iwlwifi-Qu-b0-hr-b0-62.ucode,iwlwifi-Qu-b0-hr-b0-63.ucode,iwlwifi-Qu-b0-jf-b0-48.ucode,iwlwifi-Qu-b0-jf-b0-50.ucode,iwlwifi-Qu-b0-jf-b0-53.ucode,iwlwifi-Qu-b0-jf-b0-59.ucode,iwlwifi-Qu-b0-jf-b0-62.ucode,iwlwifi-Qu-b0-jf-b0-63.ucode,iwlwifi-Qu-c0-hr-b0-48.ucode,iwlwifi-Qu-c0-hr-b0-50.ucode,iwlwifi-Qu-c0-hr-b0-53.ucode,iwlwifi-Qu-c0-hr-b0-55.ucode,iwlwifi-Qu-c0-hr-b0-59.ucode,iwlwifi-Qu-c0-hr-b0-62.ucode,iwlwifi-Qu-c0-hr-b0-63.ucode,iwlwifi-Qu-c0-jf-b0-48.ucode,iwlwifi-Qu-c0-jf-b0-50.ucode,iwlwifi-Qu-c0-jf-b0-53.ucode,iwlwifi-Qu-c0-jf-b0-55.ucode,iwlwifi-Qu-c0-jf-b0-59.ucode,iwlwifi-Qu-c0-jf-b0-62.ucode,iwlwifi-Qu-c0-jf-b0-63.ucode,iwlwifi-cc-a0-46.ucode,iwlwifi-cc-a0-48.ucode,iwlwifi-cc-a0-50.ucode,iwlwifi-cc-a0-53.ucode,iwlwifi-cc-a0-55.ucode,iwlwifi-cc-a0-59.ucode,iwlwifi-cc-a0-62.ucode,iwlwifi-cc-a0-63.ucode,iwlwifi-so-a0-gf-a0.pnvm,iwlwifi-so-a0-gf-a0-64.ucode,iwlwifi-so-a0-hr-b0-64.ucode,iwlwifi-so-a0-jf-b0-64.ucode,iwlwifi-ty-a0-gf-a0.pnvm,iwlwifi-ty-a0-gf-a0-59.ucode,iwlwifi-ty-a0-gf-a0-62.ucode,iwlwifi-ty-a0-gf-a0-63.ucode,iwlwifi-ty-a0-gf-a0-66.ucode,lgs8g75.fw,lt9611uxc_fw.bin,mt7650.bin,mts_cdma.fw,mts_edge.fw,mts_gsm.fw,mts_mt9234mu.fw,mts_mt9234zba.fw,myri10ge_ethp_big_z8e.dat,myri10ge_eth_big_z8e.dat,myri10ge_rss_ethp_big_z8e.dat,myri10ge_rss_eth_big_z8e.dat,r8a779x_usb3_v1.dlmem,r8a779x_usb3_v2.dlmem,r8a779x_usb3_v3.dlmem,regulatory.db,regulatory.db.p7s,rp2.fw,rsi_91x.fw,rt3070.bin,rt3071.bin,rt3090.bin,rt3290.bin,s5p-mfc.fw,s5p-mfc-v6.fw,s5p-mfc-v6-v2.fw,s5p-mfc-v7.fw,s5p-mfc-v8.fw,s2250.fw,s2250_loader.fw,sba200e_ecd.bin2,sdd_sagrad_1091_1098.bin,sms1xxx-hcw-55xxx-dvbt-02.fw,sms1xxx-hcw-55xxx-isdbt-02.fw,sms1xxx-nova-a-dvbt-01.fw,sms1xxx-nova-b-dvbt-01.fw,sms1xxx-stellar-dvbt-01.fw,tdmb_nova_12mhz.inp,ti_3410.fw,ti_5052.fw,tlg2300_firmware.bin,tr_smctr.bin,usbduxfast_firmware.bin,usbduxsigma_firmware.bin,usbdux_firmware.bin,v4l-cx231xx-avcore-01.fw,v4l-cx23418-apu.fw,v4l-cx23418-cpu.fw,v4l-cx23418-dig.fw,v4l-cx23885-avcore-01.fw,v4l-cx25840,vpu_d.bin,vpu_p.bin,whiteheat.fw,whiteheat_loader.fw,wil6210.br,wil6210.fw,wsm_22.bin}

