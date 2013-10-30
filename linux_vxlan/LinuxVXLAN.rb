require 'OpenNebulaNetwork'

class LinuxVXLAN < OpenNebulaNetwork
    DRIVER = "linux_vxlan"

    XPATH_FILTER = "TEMPLATE/NIC[VLAN='YES']"

    def initialize(vm, deploy_id = nil, hypervisor = nil)
        super(vm, XPATH_FILTER, deploy_id, hypervisor)
        @locking = false

        @bridges = get_interfaces
    end

    def inet_aton(ip)
        ip.split(/\./).map{|c| c.to_i}.pack("C*").unpack("N").first
    end

    def inet_ntoa(n)
        [n].pack("N").unpack("C*").join(".")
    end

    def activate
        lock

        process do |nic|
            bridge = nic[:bridge]
            phydev = nic[:phydev]

            # phydev is actually ignored but seems that it is required
            # to allow us to manage the process of adding vm to network
            # manually
            if phydev
                vni   = CONF[:vxlan_start_vni] + nic[:network_id].to_i
                vtdev = CONF[:vxlan_transit_dev]
                mbase = inet_aton('239.0.0.0')
                maddr = inet_ntoa(mbase + vni)

                exit "vxlan vni exceeds maximum" if vni > (2**24)-1

                if !bridge_exists? bridge
                    create_bridge bridge
                    ifup bridge
                end

                vxdev = "vxlan#{vni}"
                if !device_exists? vxdev
                    create_dev_vxlan(vxdev, vni, maddr, vtdev)
                    ifup vxdev
                end

                if !attached_bridge_dev?(bridge, vxdev)
                    attach_bridge_dev(bridge, vxdev)
                end
            end
        end

        unlock

        return 0
    end

    def bridge_exists?(bridge)
        @bridges.keys.include? bridge
    end

    def create_bridge(bridge)
        OpenNebula.exec_and_log("#{COMMANDS[:brctl]} addbr #{bridge}")
        @bridges[bridge] = Array.new
    end

    def delete_bridge(bridge)
        OpenNebula.exec_and_log("#{COMMANDS[:brctl]} delbr #{bridge}")
        @bridges.delete(bridge)
    end

    def device_exists?(dev)
        `#{COMMANDS[:ip]} link show #{dev}`
        $?.exitstatus == 0
    end

    def create_dev_vxlan(vxdev, vni, maddr, vtdev)
        OpenNebula.exec_and_log("#{COMMANDS[:ip]} link add #{vxdev} type vxlan id #{vni} group #{maddr} dev #{vtdev}")
    end

    def delete_dev_vxlan(vxdev)
        OpenNebula.exec_and_log("#{COMMANDS[:ip]} link delete #{vxdev} type vxlan")
    end

    def attached_bridge_dev?(bridge, dev)
        return false if !bridge_exists? bridge
        @bridges[bridge].include? dev
    end

    def attach_bridge_dev(bridge, dev)
        OpenNebula.exec_and_log("#{COMMANDS[:brctl]} addif #{bridge} #{dev}")
        @bridges[bridge] << dev
    end

    def detach_bridge_dev(bridge, dev)
        OpenNebula.exec_and_log("#{COMMANDS[:brctl]} delif #{bridge} #{dev}")
        @bridges[bridge].delete(dev)
    end

    def ifup(dev)
        OpenNebula.exec_and_log("#{COMMANDS[:ip]} link set #{dev} up")
    end

    def ifdown(dev)
        OpenNebula.exec_and_log("#{COMMANDS[:ip]} link set #{dev} down")
    end

    def deactivate
        lock

        process do |nic|
            bridge = nic[:bridge]
            phydev = nic[:phydev]

            if phydev
                vni   = CONF[:vxlan_start_vni] + nic[:network_id].to_i

                exit "vxlan vni exceeds maximum" if vni > (2**24)-1

                vxdev = "vxlan#{vni}"

                unless @bridges[bridge].any? { |dev| dev != vxdev }
                    if attached_bridge_dev?(bridge, vxdev)
                         detach_bridge_dev(bridge, vxdev)
                    end

                    if device_exists? vxdev
                        ifdown vxdev
                        delete_dev_vxlan(vxdev)
                    end

                    if bridge_exists? bridge
                        ifdown bridge
                        delete_bridge bridge
                    end
                end
            end
        end

        unlock

        return 0
    end
end
