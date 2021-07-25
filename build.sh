#!/bin/bash

mkdir -p /tmp/rom
cd /tmp/rom

# export sync start time
SYNC_START=$(date +"%s")


git config --global user.name TheGhoulEater
git config --global user.email ghouleater00@gmail.com


# Git cookies
echo "${GIT_COOKIES}" > ~/git_cookies.sh
bash ~/git_cookies.sh

# Rom repo sync & dt ( Add roms and update case functions )
rom_one(){
     repo init --depth=1 --no-repo-verify -u git://github.com/ProjectSakura/android.git -b 11 -g default,-device,-mips,-darwin,-notdefault
     repo sync -c --no-clone-bundle --no-tags --optimized-fetch --force-sync -j$(nproc --all)
     git clone https://github.com/PrajjuS/device_xiaomi_vince --single-branch -b CI device/xiaomi/vince
     git clone https://github.com/PrajjuS/vendor_xiaomi_vince --single-branch -b sakura-test-user vendor/xiaomi/vince
     git clone https://github.com/Blacksuan19/kernel_dark_ages_vince.git --single-branch -b darky kernel/xiaomi/vince
     rm -rf hardware/qcom-caf/wlan && git clone https://android.googlesource.com/platform/hardware/qcom/wlan hardware/qcom-caf/wlan
     rm -rf hardware/qcom-caf/msm8996
     git clone https://gitlab.com/PrajjuS/hardware_qcom_audio.git --single-branch -b r11.0 hardware/qcom-caf/msm8996/audio
     git clone https://gitlab.com/PrajjuS/hardware_qcom_display.git --single-branch -b r11.0 hardware/qcom-caf/msm8996/display
     git clone https://gitlab.com/PrajjuS/hardware_qcom_media.git --single-branch -b r11.0 hardware/qcom-caf/msm8996/media
     cd kernel/xiaomi/vince && git checkout darky && git revert fec013b9f5bb70c1e51285aa6e042f21f4298447 --no-edit && cd ../../..
     . build/envsetup.sh && lunch lineage_vince-user && export SAKURA_BUILD_TYPE=microg && export TARGET_USES_BLUR=true && export SAKURA_LAWNCHAIR=true && export EXTRA_FOD_ANIMATIONS=true
}

rom_two(){
     echo "Still Donno"
}

# setup TG message and build posts
telegram_message() {
	curl -s -X POST "https://api.telegram.org/bot${BOTTOKEN}/sendMessage" -d chat_id="${CHATID}" \
	-d "parse_mode=Markdown" \
	-d text="$1"
}


telegram_build() {
	curl --progress-bar -F document=@"$1" "https://api.telegram.org/bot${BOTTOKEN}/sendDocument" \
	-F chat_id="${CHATID}" \
	-F "disable_web_page_preview=true" \
	-F "parse_mode=Markdown" \
	-F caption="$2"
}


# Branch name & Head commit sha for ease of tracking
commit_sha() {
    for repo in device/xiaomi/${T_DEVICE} vendor/xiaomi/${T_DEVICE} kernel/xiaomi/${T_DEVICE}
    do
	printf "[$(echo $repo | cut -d'/' -f1 )/$(git -C ./$repo/.git rev-parse --short=10 HEAD)]"
    done
}


# Function to be chose based on rom flag in .yml
case "${rom}" in
 "ProjectSakura") rom_one
    ;;
 "donno") rom_two
    ;;
 *) echo "Invalid option!"
    exit 1
    ;;
esac


# export sync end time and diff with sync start
SYNC_END=$(date +"%s")
SDIFF=$((SYNC_END - SYNC_START))


# Send 'Build Triggered' message in TG along with sync time
telegram_message "
	*$rom Build Triggered*
        *Date:* \`$(date +"%d-%m-%Y %T")\`
        *Sync finished after $((SDIFF / 60)) minute(s) and $((SDIFF % 60)) seconds*"  &> /dev/null


# export build start time
BUILD_START=$(date +"%s")


# setup ccache
export CCACHE_DIR=/tmp/ccache
export CCACHE_EXEC=$(which ccache)
export USE_CCACHE=1
export CCACHE_COMPRESS=true
export CCACHE_COMPRESSLEVEL=1
export CCACHE_LIMIT_MULTIPLE=0.9
export CCACHE_MAXSIZE=50G
ccache -z


# Build commands for each roms on basis of rom flag in .yml / an additional full build.log is kept.
case "${rom}" in
 "ProjectSakura") mka bacon -j18 2>&1 | tee build.log
    ;;
 "donno") brunch donno  | tee build.log
    ;;
 *) echo "Invalid option!"
    exit 1
    ;;
esac


ls -a $(pwd)/out/target/product/${T_DEVICE}/ # show /out contents
BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))


# sorting final zip ( commonized considering ota zips, .md5sum etc with similiar names  in diff roms)
ZIP=$(find $(pwd)/out/target/product/${T_DEVICE}/ -maxdepth 1 -name "*${T_DEVICE}*.zip" | perl -e 'print sort { length($b) <=> length($a) } <>' | head -n 1)
ZIPNAME=$(basename ${ZIP})
ZIPSIZE=$(du -sh ${ZIP} |  awk '{print $1}')
echo "${ZIP}"


# Post Build finished with Time,duration,md5,size&Tdrive link OR post build_error&trimmed build.log in TG
telegram_post(){
 if [ -f $(pwd)/out/target/product/${T_DEVICE}/${ZIPNAME} ]; then
	rclone copy ${ZIP} vince:/Rums/${rom} -P
	MD5CHECK=$(md5sum ${ZIP} | cut -d' ' -f1)
	DWD=${TDRIVE}${rom}/${ZIPNAME}
	telegram_message "
	*Build finished after $(($DIFF / 3600)) hour(s) and $(($DIFF % 3600 / 60)) minute(s) and $(($DIFF % 60)) seconds*

	*ROM:* \`${ZIPNAME}\`
	*MD5 Checksum:* \`${MD5CHECK}\`
	*Download Link:* [Tdrive](${DWD})
	*Size:* \`${ZIPSIZE}\`
	*Commit SHA:* \`$(commit_sha)\`
	*Date:*  \`$(date +"%d-%m-%Y %T")\`" &> /dev/null
 else
	BUILD_LOG=$(pwd)/build.log
	tail -n 10000 ${BUILD_LOG} >> $(pwd)/buildtrim.txt
	LOG1=$(pwd)/buildtrim.txt
	echo "CHECK BUILD LOG" >> $(pwd)/out/build_error
	LOG2=$(pwd)/out/build_error
	TRANSFER=$(curl --upload-file ${LOG1} https://transfer.sh/$(basename ${LOG1}))
	telegram_build ${LOG2} "
	*Build failed to compile after $(($DIFF / 3600)) hour(s) and $(($DIFF % 3600 / 60)) minute(s) and $(($DIFF % 60)) seconds*

	*Build Log:* ${TRANSFER}
	*Date:*  $(date +"%d-%m-%Y %T")" &> /dev/null
 fi
}

telegram_post
ccache -s
