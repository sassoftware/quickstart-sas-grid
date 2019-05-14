#!/bin/bash
set -x

# On all sas nodes
echo "$HOSTNAME"

sudo -u root bash << EOF
if ! grep -q "@sas" /etc/security/limits.conf; then
    echo "@sas             hard    nofile         20480" >> /etc/security/limits.conf 
    echo "@sas             soft    nofile         20480" >> /etc/security/limits.conf 
    echo "@sas             hard    nproc          20480" >> /etc/security/limits.conf 
    echo "@sas             soft    nproc          20480" >> /etc/security/limits.conf 
fi

if ! grep -q "SASFoundation" /etc/profile; then  
    echo 'export PATH=$PATH:/usr/local/SASHome/SASFoundation/9.4' >> /etc/profile
fi

if ! grep -q "ulimit" /home/sasinst/.bash_profile; then
    echo "ulimit -n 20480" >> /home/sasinst/.bash_profile
    echo "ulimit -u 20480" >> /home/sasinst/.bash_profile
fi

cd /usr/local
rm -Rf config2/* 
exit
EOF

sudo -u sasinst bash << EOF
cd /sas/$1                        
./setup.sh -deploy -quiet -responsefile /sas/quickstart/playbooks/templates/midtier_install.txt
exit
EOF

sudo -u root bash << EOF
/usr/local/SASHome/SASFoundation/9.4/utilities/bin/setuid.sh
exit
EOF

sudo -u sasinst bash << EOF
cd /sas/$1                        
./setup.sh -deploy -quiet -responsefile /sas/quickstart/playbooks/templates/midtier_config.txt -skipadmincheck
exit
EOF

#sudo -u root bash << EOF
#echo '-WORK /saswork' >> /sas/SASHome/SASFoundation/9.4/nls/en/sasv9.cfg
#/sas/SASHome/SASFoundation/9.4/utilities/bin/setuid.sh
#. /sas/studioconfig/sasstudio.sh start
#exit
#EOF
