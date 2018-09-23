#!/bin/sh
#-
# Copyright (c) 2018 Kris Moore
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
# $FreeBSD$
#

export PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin"

POUDRIERE_BASEFS=${POUDRIERE_BASEFS:-/usr/local/poudriere}
POUDRIERE_BASE=${POUDRIERE_BASE:-trueos-mk-base}
POUDRIERE_PORTS=${POUDRIERE_PORTS:-trueos-mk-ports}
PKG_CMD=${PKG_CMD:-pkg-static}

POUDRIERE_PORTDIR="${POUDRIERE_BASEFS}/ports/${POUDRIERE_PORTS}"
POUDRIERE_PKGDIR="${POUDRIERE_BASEFS}/data/packages/${POUDRIERE_BASE}-${POUDRIERE_PORTS}"
if [ -e /usr/bin/poudriere ] ; then
	# To help us transition builders, remove this eventually
	POUDRIERED_DIR=/etc/poudriere.d
else
	POUDRIERED_DIR=/usr/local/etc/poudriere.d
fi

exit_err()
{
	echo "ERROR: $1"
	if [ -n "$2" ] ; then
		exit $2
	else
		exit 1
	fi
}

env_check()
{
	if [ -z "$TRUEOS_MANIFEST" ] ; then
		exit_err "Unset TRUEOS_MANIFEST"
	fi
	echo "Using TRUEOS_MANIFEST: $TRUEOS_MANIFEST"
	PORTS_TYPE=$(jq -r '."ports"."type"' $TRUEOS_MANIFEST)
	PORTS_URL=$(jq -r '."ports"."url"' $TRUEOS_MANIFEST)
	PORTS_BRANCH=$(jq -r '."ports"."branch"' $TRUEOS_MANIFEST)

	case $PORTS_TYPE in
		git) if [ -z "$PORTS_BRANCH" ] ; then
			exit_err "Empty ports.branch!"
		     fi ;;
              local) ;;
		tar) ;;
		*) exit_err "Unknown or unspecified ports.type!" ;;
	esac

	if [ -z "$PORTS_URL" ] ; then
		exit_err "Empty ports.url!"
	fi

	if [ ! -d '/usr/ports/distfiles' ] ; then
		mkdir /usr/ports/distfiles
	fi
}

setup_poudriere_conf()
{
	echo "Setting up poudriere configuration"
	ZPOOL=$(mount | grep 'on / ' | cut -d '/' -f 1)
	_pdconf="${POUDRIERED_DIR}/${POUDRIERE_BASE}-poudriere.conf"
	_pdconf2="${POUDRIERED_DIR}/${POUDRIERE_PORTS}-poudriere.conf"

	if [ ! -d "${POUDRIERED_DIR}" ] ; then
		mkdir -p ${POUDRIERED_DIR}
	fi

	# Copy the systems poudriere.conf over
	cat ${SRCDIR}/release/poudriere.conf \
		| grep -v "ZPOOL=" \
		| grep -v "FREEBSD_HOST=" \
		| grep -v "GIT_PORTSURL=" \
		| grep -v "USE_TMPFS=" \
		| grep -v "BASEFS=" \
		> ${_pdconf}
	echo "Using zpool: $ZPOOL"
	echo "ZPOOL=$ZPOOL" >> ${_pdconf}
	echo "Using Dist Directory: $DIST_DIR"
	echo "FREEBSD_HOST=file://${DIST_DIR}" >> ${_pdconf}
	echo "Using Ports Tree: $PORTS_URL"
	if [ "$PORTS_TYPE" = "git" ] ; then
		echo "GIT_URL=${PORTS_URL}" >> ${_pdconf}
	fi
	echo "USE_TMPFS=data" >> ${_pdconf}
	echo "BASEFS=$POUDRIERE_BASEFS" >> ${_pdconf}
	echo "ATOMIC_PACKAGE_REPOSITORY=no" >> ${_pdconf}
	echo "PKG_REPO_FROM_HOST=yes" >> ${_pdconf}
	echo "ALLOW_MAKE_JOBS_PACKAGES=\"chromium* iridium* gcc* webkit* llvm* clang* firefox* ruby* cmake* rust* qt5-web* phantomjs* swift* python2* python3* perl5* pypy*\"" >> ${_pdconf}
	echo "PRIORITY_BOOST=\"pypy* openoffice* iridium* chromium*\"" >> ${_pdconf}

	if [ "$(jq -r '."poudriere-conf" | length' ${TRUEOS_MANIFEST})" != "0" ] ; then
		jq -r '."poudriere-conf" | join("\n")' ${TRUEOS_MANIFEST} >> ${_pdconf}
	fi

	# If there is a custom poudriere.conf.release file in /etc we will also
	# include it. This can be used to set different tmpfs or JOBS on a per system
	# basis
	if [ -e "/etc/poudriere.conf.release" ] ; then
		cat /etc/poudriere.conf.release >> ${_pdconf}
	fi

	# Need config for the ports tree also
	cp ${_pdconf} ${_pdconf2}
}

setup_poudriere_jail()
{
	echo "Setting up poudriere jail"

	# Locate the worldstagedir
	if [ -e "${OBJDIR}/../worldstage" ] ; then
		JDIR="${OBJDIR}/../worldstage"
	elif [ -e "${OBJDIR}/worldstage" ] ; then
		JDIR="${OBJDIR}/worldstage"
	else
		exit_err "Unable to locate worldstage dir"
	fi

	# Copy llvm60 to the jail dir
	rm -rf ${JDIR}/usr/local
	mkdir -p ${JDIR}/usr/local/lib 2>/dev/null
	cp -a /usr/local/llvm60 ${JDIR}/usr/local/
	if [ $? -ne 0 ] ; then
		exit_err "Failed copying /usr/local/llvm60 -> ${JDIR}/usr/local/"
	fi

	# Copy libxml2*
	cp -a /usr/local/lib/libxml* ${JDIR}/usr/local/llvm60/lib/
	if [ $? -ne 0 ] ; then
		exit_err "Failed copying /usr/local/lib/libxml* -> ${JDIR}/usr/local/lib"
	fi

	# Copy libedit
	cp -a /usr/local/lib/libedit* ${JDIR}/usr/local/llvm60/lib/
	if [ $? -ne 0 ] ; then
		exit_err "Failed copying /usr/local/lib/libedit* -> ${JDIR}/usr/local/lib"
	fi

	# Copy over the sources
	mkdir -p ${JDIR}/usr/src 2>/dev/null
	cp -a ${SRCDIR}/ ${JDIR}/usr/src/
	if [ $? -ne 0 ] ; then
		exit_err "Failed copying ${SRCDIR} -> ${JDIR}/usr/src"
	fi

	# Setup the sym-links inside the jail
	chroot ${JDIR} clang-bootstrap llvm60
	if [ $? -ne 0 ] ; then
		exit_err "Failed clang-bootstrap in -> ${JDIR}"
	fi

	# Make sure the various /tmp(s) will work for poudriere
	chmod 777 ${JDIR}/tmp
	chmod 777 ${JDIR}/var/tmp

	# Create new jail
	poudriere jail -c -j $POUDRIERE_BASE -m null -M ${JDIR} -v ${OSRELEASE}
	if [ $? -ne 0 ] ; then
		exit_err "Failed creating poudriere jail"
	fi

	# Create the new ports tree
	echo "Setting up poudriere ports"
	if [ "$PORTS_TYPE" = "git" ] ; then
		poudriere ports -c -p $POUDRIERE_PORTS -m git -B $PORTS_BRANCH
		if [ $? -ne 0 ] ; then
			exit_err "Failed creating poudriere ports"
		fi
	elif [ "$PORTS_TYPE" = "tar" ] ; then
		echo "Fetching ports tarball"
		fetch -o ${OBJDIR}/ports.tar ${PORTS_URL}
		if [ $? -ne 0 ] ; then
			exit_err "Failed fetching poudriere ports"
		fi

		rm -rf ${OBJDIR}/ports-tree
		mkdir -p ${OBJDIR}/ports-tree

		echo "Extracting ports tarball"
		tar xvf ${OBJDIR}/ports.tar -C ${OBJDIR}/ports-tree 2>/dev/null
		if [ $? -ne 0 ] ; then
			exit_err "Failed extracting poudriere ports"
		fi

		poudriere ports -c -p $POUDRIERE_PORTS -m null -M ${OBJDIR}/ports-tree
		if [ $? -ne 0 ] ; then
			exit_err "Failed creating poudriere ports"
		fi
	else
		# Doing a nullfs mount of existing directory
		poudriere ports -c -p $POUDRIERE_PORTS -m null -M ${PORTS_URL}
		if [ $? -ne 0 ] ; then
			exit_err "Failed creating poudriere ports"
		fi
	fi

	rm /etc/poudriere.d/${POUDRIERE_BASE}-make.conf
	for c in $(jq -r '."ports"."make.conf" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
	do
		eval "CHECK=\$$c"
		if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi

		# We have a conditional set of packages to include, lets do it
		jq -r '."ports"."make.conf"."'$c'" | join("\n")' ${TRUEOS_MANIFEST} >>/etc/poudriere.d/${POUDRIERE_BASE}-make.conf
	done

	# Save the list of build flags
}

get_explicit_pkg_deps()
{
	retdeps=""
	ls ${OBJDIR}/../worldstage/*.ucl >/dev/null 2>/dev/null
	if [ $? -ne 0 ] ; then
		echo "ERROR: Failed to locate UCL files in ${OBJDIR}/../worldstage/" >&2
		return 1
	fi
	for ucl in `ls ${OBJDIR}/../worldstage/*.ucl`
	do
		grep -q "deps" ${ucl}
		if [ $? -ne 0 ] ; then
			continue
		fi
		# Check for filters to skip
		# This is used when building list for ISO and we don't want things
		# like development or debug package depends
		if [ -n "$1" ] ; then
			skip="0"
			for i in $1
			do
				echo ${ucl} | grep -q "$i"
				if [ $? -eq 0 ] ; then
					skip=1
				fi
			done
			if [ "$skip" = "1" ] ; then continue ; fi
		fi
		echo "Searching UCL ${ucl} for package depends" >&2
		pdeps=$(uclcmd get --file ${ucl} -j deps 2>/dev/null | jq -r '.[]."origin"' 2>/dev/null | grep -v '^base$' | tr -s '\n' ' ')
		if [ -n "$pdeps" ] ; then
			retdeps="$pdeps $retdeps"
		fi
	done
	if [ -n "$retdeps" ] ; then
		echo $retdeps
		return 0
	else
		return 1
	fi
}

get_pkg_build_list()
{
	# Check for any conditional packages to build
	for pkgstring in packages essential-packages
	do
		for c in $(jq -r '."'$pkgstring'" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
		do
			eval "CHECK=\$$c"
			if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi

			echo "Getting packages in JSON $pkgstring -> $c"
			# We have a conditional set of packages to include, lets do it
			jq -r '."'$pkgstring'"."'$c'" | join("\n")' ${TRUEOS_MANIFEST} >> ${1} 2>/dev/null
		done
	done

	# Get the explicit packages
	get_explicit_pkg_deps | tr -s ' ' '\n' >> ${1}

	# Sort and remove dups
	cat ${1} | sort -r | uniq > ${1}.new
	mv ${1}.new ${1}
}

build_poudriere()
{
	# Check if we want to do a bulk build of everything
	if [ $(jq -r '."package-all"' ${TRUEOS_MANIFEST}) = "true" ] ; then
		# Start the build
		echo "Starting poudriere FULL build"
		poudriere bulk -a -j $POUDRIERE_BASE -p ${POUDRIERE_PORTS}
		check_essential_pkgs
		if [ $? -ne 0 ] ; then
			exit_err "Failed building all essential packages.."
		fi
	else
		rm ${OBJDIR}/trueos-mk-bulk-list 2>/dev/null
		echo "Starting poudriere SELECTIVE build"
		get_pkg_build_list ${OBJDIR}/trueos-mk-bulk-list

		echo "Starting poudriere to build:"
		echo "------------------------------------"
		cat ${OBJDIR}/trueos-mk-bulk-list

		# Start the build
		echo "Starting: poudriere bulk -f ${OBJDIR}/trueos-mk-bulk-list -j $POUDRIERE_BASE -p ${POUDRIERE_PORTS}"
		echo "------------------------------------"
		poudriere bulk -f ${OBJDIR}/trueos-mk-bulk-list -j $POUDRIERE_BASE -p ${POUDRIERE_PORTS}
		if [ $? -ne 0 ] ; then
			exit_err "Failed poudriere build"
		fi

	fi

	# Save the FreeBSD ABI Version
	awk '/^\#define[[:blank:]]__FreeBSD_version/ {print $3}' < ${SRCDIR}/sys/sys/param.h > ${POUDRIERE_PKGDIR}/.FreeBSD_Version

}

clean_poudriere()
{
	# Kill previous jail
	poudriere jail -k -j $POUDRIERE_BASE -p ${POUDRIERE_PORTS}

	# Delete previous jail
	echo "poudriere jail -d -j ${POUDRIERE_BASE}"
	echo -e "y\n" | poudriere jail -d -j ${POUDRIERE_BASE}

	# Delete previous ports tree
	echo -e "y\n" | poudriere ports -d -p ${POUDRIERE_PORTS}

	# Make sure the pkgdir exists
	if [ ! -d "${POUDRIERE_PKGDIR}" ] ; then
		mkdir -p "${POUDRIERE_PKGDIR}/All"
	fi

	# Figure out the BASE PREFIX for base packages
	BASENAME=$(jq -r '."base-packages"."name-prefix"' ${TRUEOS_MANIFEST})
	if [ "$BASENAME" = "null" ] ; then
		BASENAME="FreeBSD"
	fi


	# Move over previously built pkgs
	PSETDIR="${OBJDIR}/../../pkgset"
	if [ -d "$PSETDIR" ] ; then
		echo "Re-using existing packages from: $PSETDIR"
		rm -f ${PSETDIR}/All/${BASENAME}-*
		mkdir -p ${POUDRIERE_PKGDIR}/All 2>/dev/null
		mv ${PSETDIR}/All/* ${POUDRIERE_PKGDIR}/All
		rm -rf ${PSETDIR}
	fi

	# If the ABI has changed, we need to rebuild all
	ABIVER=$(awk '/^\#define[[:blank:]]__FreeBSD_version/ {print $3}' < ${SRCDIR}/sys/sys/param.h)
	if [ "$(cat ${POUDRIERE_PKGDIR}/.FreeBSD_Version 2>/dev/null)" != "$ABIVER" ] ; then
		echo "New ABI detected! Removing stale packages..."
		rm -rf ${POUDRIERE_PKGDIR}
	fi
}

super_clean_poudriere()
{
	#Look for any leftover mountpoints/directories and remove them too
	for i in `ls ${POUDRIERED_DIR}/*-make.conf 2>/dev/null`
	do
		name=`basename "${i}" | sed 's|-make.conf||g'`
		if [ ! -d "${POUDRIERED_DIR}/jails/${name}" ]  && [ -d "${POUDRIERE_BASEFS}/jails/${name}" ] ; then
			#Jail configs missing, but jail mountpoint still exists
			#Need to completely destroy the old jail dataset/dir
			_stale_dataset=$(mount | grep 'on ${POUDRIERE_BASEFS}/jails/${name} ' | cut -w -f 1)
			if [ -n "${_stale_dataset}" ] ; then
				#Found a stale mountpoint/dataset
				umount ${POUDRIERE_BASEFS}/jails/${name}
				rmdir ${POUDRIERE_BASEFS}/jails/${name}
				#Verify that it is a valid ZFS dataset
				zfs list "${_stale_dataset}"
				if [ 0 -eq $? ] ; then
					zfs destroy -r ${_stale_dataset}
				fi
			fi
		fi
	done
}

check_essential_pkgs()
{
	echo "Checking essential-packages..."
	local haveWarn=0

	ESSENTIAL=""

	# Check for any conditional packages to build
	for ptype in essential-packages auto-install-packages iso-install-packages dist-packages
	do
		for c in $(jq -r '."'$ptype'" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
		do
			eval "CHECK=\$$c"
			if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi

			# We have a conditional set of packages to include, lets do it
			ESSENTIAL="$ESSENTIAL $(jq -r '."'$ptype'"."'$c'" | join(" ")' ${TRUEOS_MANIFEST})"
		done
	done

	# Get the explicit depends from base system
	ESSENTIAL="$ESSENTIAL $(get_explicit_pkg_deps)"

	# Cleanup whitespace
	ESSENTIAL=$(echo $ESSENTIAL | awk '{$1=$1;print}')

	if [ -z "$ESSENTIAL" ] ; then
		echo "No essential-packages defined. Skipping..."
		return 0
	fi

	for i in $ESSENTIAL
	do

		if [ ! -d "${POUDRIERE_PORTDIR}/${i}" ] ; then
			echo "Invalid PORT: $i"
			continue
		fi

		# Get the pkgname
		unset pkgName
		pkgName=$(make -C ${POUDRIERE_PORTDIR}/${i} -V PKGNAME PORTSDIR=${POUDRIERE_PORTDIR} __MAKE_CONF=${OBJDIR}/poudriere.d/${POUDRIERE_BASE}-${POUDRIERE_PORTS}-make.conf)
		if [ -z "${pkgName}" ] ; then
			echo "Could not get PKGNAME for ${i}"
			haveWarn=1
		fi

		if [ ! -e "${POUDRIERE_PKGDIR}/All/${pkgName}.txz" ] ; then
			echo "Checked: ${POUDRIERE_PKGDIR}/All/${pkgName}.txz"
			echo "WARNING: Missing package ${pkgName} for port ${i}"
			haveWarn=1
		else
			echo "Verified: ${pkgName}"
		fi
   done

   return $haveWarn
}

clean_jails()
{
	setup_poudriere_conf
	clean_poudriere
	super_clean_poudriere
}

run_poudriere()
{
	clean_jails
	setup_poudriere_jail
	build_poudriere
	merge_pkg_sets
}

merge_pkg_sets()
{
	PDIR="${OBJROOT}pkgset"

	# Prep our pkgset directory
	rm -rf ${PDIR} 2>/dev/null
	mkdir -p ${PDIR}/All

	RELMAJ=$(echo $OSRELEASE | cut -d '.' -f 1 | cut -d '-' -f 2)
	ABI_DIR="FreeBSD:$RELMAJ:`uname -m`"

	# Copy the base packages
	#
	# Why a copy? So we can re-run port builds with 'make ports'
	# and still have our pristine set here for reference
	cp ${OBJROOT}repo/${ABI_DIR}/latest/* ${PDIR}/All/
	if [ $? -ne 0 ] ; then
		exit_err "Failed staging base packages..."
	fi

	# Move the port packages
	mv ${POUDRIERE_PKGDIR}/All/* ${PDIR}/All/
	if [ $? -ne 0 ] ; then
		exit_err "Failed staging ports packages..."
	fi
}

mk_repo_config()
{
	rm -rf ${OBJDIR}/repo-config
	mkdir -p ${OBJDIR}/repo-config

	cat >${OBJDIR}/repo-config/repo.conf <<EOF
base: {
  url: "file://${PKG_DIR}",
  signature_type: "none",
  enabled: yes
}
EOF
	PKG_VERSION=$(readlink ${PKG_DIR}/../repo/${ABI_DIR}/latest)
	mkdir -p ${TARGET_DIR}/${ABI_DIR}/${PKG_VERSION}
	ln -s ${PKG_VERSION} ${TARGET_DIR}/${ABI_DIR}/latest
}

cp_iso_pkgs()
{
	mk_repo_config

	# Figure out the BASE PREFIX for base packages
	BASENAME=$(jq -r '."base-packages"."name-prefix"' ${TRUEOS_MANIFEST})
	if [ "$BASENAME" = "null" ] ; then
		BASENAME="FreeBSD"
	fi

	# Copy over the base system packages
	pkg-static -o ABI_FILE=${OBJDIR}/disc1/bin/sh \
		-R ${OBJDIR}/repo-config \
		fetch -y -d -o ${TARGET_DIR}/${ABI_DIR}/${PKG_VERSION} -g ${BASENAME}-*
	if [ $? -ne 0 ] ; then
		exit_err "Failed copying base packages to ISO..."
	fi

	# Check if we have dist-packages to include on the ISO
	for c in $(jq -r '."dist-packages" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
	do
		eval "CHECK=\$$c"
		if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi
		for i in $(jq -r '."dist-packages"."'$c'" | join(" ")' ${TRUEOS_MANIFEST})
		do
			pkg-static -o ABI_FILE=${OBJDIR}/disc1/bin/sh \
				-R ${OBJDIR}/repo-config \
				fetch -y -d -o ${TARGET_DIR}/${ABI_DIR}/${PKG_VERSION} $i
				if [ $? -ne 0 ] ; then
					exit_err "Failed copying dist-package $i to ISO..."
				fi
		done
	done

	rm ${OBJDIR}/disc1/root/auto-dist-install 2>/dev/null
	# Check if we have auto-install-packages to include on the ISO
	for c in $(jq -r '."auto-install-packages" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
	do
		eval "CHECK=\$$c"
		if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi
		for i in $(jq -r '."dist-packages"."'$c'" | join(" ")' ${TRUEOS_MANIFEST})
		do
			pkg-static -o ABI_FILE=${OBJDIR}/disc1/bin/sh \
				-R ${OBJDIR}/repo-config \
				fetch -y -d -o ${TARGET_DIR}/${ABI_DIR}/${PKG_VERSION} $i
				if [ $? -ne 0 ] ; then
					exit_err "Failed copying dist-package $i to ISO..."
				fi
		done

		echo "Saving package list to auto-install"
		jq -r '."auto-install-packages"."'$c'" | join(" ")' ${TRUEOS_MANIFEST} \
			 >>${OBJDIR}/disc1/root/auto-dist-install
	done


	# Create the repo DB
	echo "Creating installer pkg repo"
	pkg-static repo ${TARGET_DIR}/${ABI_DIR}/${PKG_VERSION}


	# Check if we have any post install commands to run
	if [ "$(jq -r '."post-install-commands" | length' ${TRUEOS_MANIFEST})" != "0" ] ; then
		echo "Saving post-install commands"
		jq -r '."post-install-commands"' ${TRUEOS_MANIFEST} \
			 >${OBJDIR}/disc1/root/post-install-commands.json
	fi

	# Create the install repo DB config
	mkdir -p ${OBJDIR}/disc1/etc/pkg
	cat >${OBJDIR}/disc1/etc/pkg/TrueOS.conf <<EOF
install-repo: {
  url: "file:///install-pkg",
  signature_type: "none",
  enabled: yes
}
EOF
	mkdir -p ${OBJDIR}/disc1/install-pkg
	mount_nullfs ${PKG_DIR} ${OBJDIR}/disc1/install-pkg

	# Check for explict pkgs to install, minus development and debug
	for e in $(get_explicit_pkg_deps "development debug")
	do
		pkg-static -o ABI_FILE=/bin/sh \
			-R /etc/pkg \
			-c ${OBJDIR}/disc1 \
			install -y $e
			if [ $? -ne 0 ] ; then
				exit_err "Failed installing package $i to ISO..."
			fi

	done

	# Check for conditionals packages to install
	for c in $(jq -r '."iso-install-packages" | keys[]' ${TRUEOS_MANIFEST} 2>/dev/null | tr -s '\n' ' ')
	do
		eval "CHECK=\$$c"
		if [ -z "$CHECK" -a "$c" != "default" ] ; then continue; fi

		# We have a conditional set of packages to include, lets do it
		for i in $(jq -r '."iso-install-packages"."'$c'" | join(" ")' ${TRUEOS_MANIFEST})
		do
			pkg-static -o ABI_FILE=/bin/sh \
				-R /etc/pkg \
				-c ${OBJDIR}/disc1 \
				install -y $i
				if [ $? -ne 0 ] ; then
					exit_err "Failed installing package $i to ISO..."
				fi
		done
	done

	# Cleanup the ISO install packages
	umount -f ${OBJDIR}/disc1/install-pkg
	rmdir ${OBJDIR}/disc1/install-pkg
	rm ${OBJDIR}/disc1/etc/pkg/TrueOS.conf

	# Create the local repo DB config
	cat >${OBJDIR}/disc1/etc/pkg/TrueOS.conf <<EOF
install-repo: {
  url: "file:///dist/${ABI_DIR}/latest",
  signature_type: "none",
  enabled: yes
}
EOF

}

apply_iso_config()
{

	# Check for a custom install script
	_jsins=$(jq -r '."install-script"' ${TRUEOS_MANIFEST})
	if [ "$_jsins" != "null" -a -n "$_jsins" ] ; then
		echo "Setting custom install script"
		jq -r '."install-script"' ${TRUEOS_MANIFEST} \
			 >${OBJDIR}/disc1/etc/trueos-custom-install
	fi

	# Check for auto-install script
	_jsauto=$(jq -r '."auto-install-script"' ${TRUEOS_MANIFEST})
	if [ "$_jsauto" != "null" -a -n "$_jsauto" ] ; then
		echo "Setting auto install script"
		cp $(jq -r '."auto-install-script"' ${TRUEOS_MANIFEST}) \
			 ${OBJDIR}/disc1/etc/installerconfig
	fi

}

env_check

case $1 in
	clean) clean_jails ; exit 0 ;;
	poudriere) run_poudriere ;;
	iso) cp_iso_pkgs
	     apply_iso_config
	     ;;
	*) echo "Unknown option selected" ;;
esac

exit 0
