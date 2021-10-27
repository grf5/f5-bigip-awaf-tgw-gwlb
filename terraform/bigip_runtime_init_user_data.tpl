#!/bin/bash

# Create the config and logging directories
mkdir -p  /var/log/cloud /config/cloud

# Log to file and stdout
LOG_FILE=/var/log/cloud/startup-script.log
[[ ! -f $LOG_FILE ]] && touch $LOG_FILE || { echo "Run Only Once. Exiting"; exit; }
npipe=/tmp/$$.tmp
trap "rm -f $npipe" EXIT
mknod $npipe p
tee <$npipe -a $LOG_FILE /dev/ttyS0 &
exec 1>&-
exec 1>$npipe
exec 2>&1

# Create the manual run shell script
cat << "EOF" > /config/cloud/manual_run.sh
#!/bin/bash

# Set logging level (least to most)
# error, warn, info, debug, silly
export F5_BIGIP_RUNTIME_INIT_LOG_LEVEL=silly

# runtime init execution, with telemetry skipped
f5-bigip-runtime-init --config-file /config/cloud/runtime-init-conf.json --skip-telemetry
EOF

# create the health check iRule file for import
cat << "EOF" > /config/cloud/aws_gwlb_health_check.tcl
ltm rule aws_gwlb_health_check {
when HTTP_REQUEST {
    HTTP::respond 200 content OK
    HTTP::close
    return
  }
}
EOF

cat << "EOF" > /config/cloud/runtime-init-conf.json
{
    "runtime_parameters": [
        {
            "name": "MGMT_IP",
            "type": "metadata",
            "metadataProvider": {
                "environment": "aws",
                "type": "network",
                "field": "local-ipv4s",
                "index": 0
            }
        },
        {
            "name": "MGMT_GATEWAY",
            "type": "metadata",
            "metadataProvider": {
                "environment": "aws",
                "type": "network",
                "field": "local-ipv4s",
                "index": 0,
                "ipcalc": "first"
            }
        }
    ],
    "pre_onboard_enabled": [
        {
            "name": "provision_rest",
            "type": "inline",
            "commands": [
                "/usr/bin/setdb provision.extramb 500",
                "/usr/bin/setdb restjavad.useextramb true"
            ]
        }
    ],
    "bigip_ready_enabled": [
        {
            "name": "licensing",
            "type": "inline",
            "commands": [
                "if [ \"${bigipLicenseType}\" = \"BYOL\" ]; then tmsh install sys license registration-key ${bigipLicense}; fi"
            ]
        }
    ],
    "extension_packages": {
        "install_operations": [
            {
                "extensionType": "do",
                "extensionVersion": "1.21.1",
                "extensionUrl": "https://github.com/F5Networks/f5-declarative-onboarding/releases/download/v1.21.1/f5-declarative-onboarding-1.21.1-2.noarch.rpm",
                "extensionHash": "4ddf98bfec0f6272ac1c76a81b806fc1f16bae03f39a74e2468b2b0e7b96be09"
            },
            {
                "extensionType": "as3",
                "extensionVersion": "3.26.1",
                "extensionUrl": "https://github.com/F5Networks/f5-appsvcs-extension/releases/download/v3.26.1/f5-appsvcs-3.26.1-1.noarch.rpm",
                "extensionHash": "1a5c3c754165a6b7739a15e1f80e4caa678a1fa8fc1b3033e61992663295cf81"
            }
        ]
    },
    "post_onboard_enabled": [
        {
            "name": "manual_tmsh_configuration",
            "type": "inline",
            "commands": [
                "source /usr/lib/bigstart/bigip-ready-functions; wait_bigip_ready",
                "tmsh modify sys provision ltm level nominal",
                "source /usr/lib/bigstart/bigip-ready-functions; wait_bigip_ready",
                "tmsh modify sys provision asm level nominal",
                "source /usr/lib/bigstart/bigip-ready-functions; wait_bigip_ready",
                "tmsh modify sys global-settings gui-setup disabled",
                "tmsh modify auth user admin password ${bigipAdminPassword}",
                "tmsh modify sys ntp servers add { 0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org }",
                "tmsh create net vlan dataplane interfaces add { 1.1 { untagged }} mtu 9001",
                "tmsh create net route-domain dataplane id 1 vlans add { dataplane }",
                "tmsh create net self inband-mgmt address `printf {{{ MGMT_IP }}} | cut -d \"/\" -f1`%1/`printf {{{ MGMT_IP }}} | cut -d \"/\" -f2` vlan dataplane allow-service all",
                "tmsh create net route dataplane-default network 0.0.0.0%1 gw {{{ MGMT_GATEWAY }}}%1",
                "tmsh create net tunnels tunnel geneve local-address `printf {{{ MGMT_IP }}} | cut -d \"/\" -f1`%1 remote-address any%1 profile geneve",
                "tmsh modify net route-domain dataplane vlans add { geneve }",
                "tmsh load sys config merge file /config/cloud/aws_gwlb_health_check.tcl",
                "tmsh create ltm virtual aws_gwlb_health_check destination `printf {{{ MGMT_IP }}} | cut -d \"/\" -f1`%1:65530 ip-protocol tcp mask 255.255.255.255 profiles add { http tcp } source 0.0.0.0%1/0 vlans-enabled vlans add { dataplane } rules { aws_gwlb_health_check }",
                "tmsh create net self geneve-tunnel address 10.131.0.1%1/24 vlan geneve allow-service all",
                "tmsh create net arp fake_arp_entry ip-address 10.131.0.2%1 mac-address ff:ff:ff:ff:ff:ff",
                "tmsh create ltm node geneve-tunnel address 10.131.0.2%1 monitor none",
                "tmsh create ltm pool geneve-tunnel members add { geneve-tunnel:0 } monitor none",
                "tmsh create ltm virtual forwarding_vs destination 0.0.0.0%1:any ip-protocol any vlans-enabled vlans add { geneve } translate-address disabled source-port preserve-strict pool geneve-tunnel mask any",
                "tmsh modify sys db provision.managementeth value eth1",
                "tmsh save /sys config",
                "sed -i 's/        1\\.1 {/        1\\.0 {/g' /config/bigip_base.conf",
                "reboot"
            ]
        }
    ]
}
EOF

### runcmd:

# Download the f5-bigip-runtime-init package
# 30 attempts, 5 second timeout and 10 second pause between attempts
for i in {1..30}; do
    curl -fv --retry 1 --connect-timeout 5 -L https://cdn.f5.com/product/cloudsolutions/f5-bigip-runtime-init/v1.2.1/dist/f5-bigip-runtime-init-1.2.1-1.gz.run -o /var/config/rest/downloads/f5-bigip-runtime-init-1.2.1-1.gz.run && break || sleep 10
done

# Set logging level (least to most)
# error, warn, info, debug, silly
export F5_BIGIP_RUNTIME_INIT_LOG_LEVEL=silly

# Execute the installer
bash /var/config/rest/downloads/f5-bigip-runtime-init-1.2.1-1.gz.run -- "--cloud aws"

# Runtime Init execution on configuration file created above
f5-bigip-runtime-init --config-file /config/cloud/runtime-init-conf.json