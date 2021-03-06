require "log4r"
require "vagrant"

module VagrantPlugins
  module ProviderKvm
    class Provider < Vagrant.plugin("2", :provider)
      attr_reader :driver
      attr_reader :machine

      def initialize(machine)
        @logger  = Log4r::Logger.new("vagrant_kvm")
        @machine = machine

        # This method will load in our driver, so we call it now to
        # initialize it.
        machine_id_changed
      end

      def action(name)
        # Attempt to get the action method from the Action class if it
        # exists, otherwise return nil to show that we don't support the
        # given action.
        action_method = "action_#{name}"
        return Action.send(action_method) if Action.respond_to?(action_method)
        nil
      end

      # If the machine ID changed, then we need to rebuild our underlying
      # driver.
      def machine_id_changed
        id = @machine.id

        begin
          @logger.debug("Instantiating the driver for machine ID: #{@machine.id.inspect}")
          @driver = Driver::Driver.new(id)
        rescue Driver::Driver::VMNotFound
          # The virtual machine doesn't exist, so we probably have a stale
          # ID. Just clear the id out of the machine and reload it.
          @logger.debug("VM not found! Clearing saved machine ID and reloading.")
          id = nil
          retry
        end
      end

      # Returns the SSH info for accessing the VM.
      def ssh_info
        # If the VM is not created then we cannot possibly SSH into it, so
        # we return nil.
        return nil if state == :not_created

        #ip_addr = @driver.read_ip(@machine.config.vm.base_mac)
        return {
          :host => read_machine_ip,
          :port => "22" # XXX should be somewhere in default config
        }
      end

      require 'socket'
      def my_first_private_ipv4
        Socket.ip_address_list.detect{|intf| intf.ipv4_private?}
      end

      def fill_arp_table
        addr = my_first_private_ipv4

        begin
          route =`ip route show`.split("\n")
        rescue
          @logger.debug("Can't get routing table addr: #{addr.ip_address}.")
        end

        line = route.detect { |r| r.include?(addr.ip_address) }
        line =~ /^(\d+\.\d+\.\d+\.\d+\/\d+)/
        net = $1.split("/")[0]

        begin
          `nmap -sP #{net}/24`.split("\n")
        rescue
          @logger.debug("Not filling ARP table with nmap for #{net}.")
        end
      end

      # XXX duplicated from prepare_nfs_settings
      # Returns the IP address of the guest by looking at the first
      # enabled host only network.
      #
      # @return [String]
      def read_machine_ip
        conn = Util::LibvirtHelper.connect
        xml = conn.lookup_domain_by_uuid(@machine.id).xml_desc
        xml =~ /<mac address='(.+)'\/>/
        mac = $1
        line = ''
        arp_filled=false

        180.times do
          arp = `arp -n`.split("\n")
          line = arp.detect { |l| l.include?(mac) }
          if line
            break
          else
            unless arp_filled
              fill_arp_table
              arp_filled = true
            end
            sleep(1)
          end
#          line ? break : sleep(1)
        end
        line =~ /(\d+\.\d+\.\d+\.\d+)/
        Util::LibvirtHelper.disconnect(conn)

        $1
      end

      # Return the state of the VM
      #
      # @return [Symbol]
      def state
        # XXX: What happens if we destroy the VM but the UUID is still
        # set here?

        # Determine the ID of the state here.
        state_id = nil
        state_id = :not_created if !@driver.uuid
        state_id = @driver.read_state if !state_id
        state_id = :unknown if !state_id

        # TODO Translate into short/long descriptions
        short = state_id
        long  = I18n.t("vagrant.commands.status.#{state_id}")

        # Return the state
        Vagrant::MachineState.new(state_id, short, long)
      end

      # Returns a human-friendly string version of this provider which
      # includes the machine's ID that this provider represents, if it
      # has one.
      #
      # @return [String]
      def to_s
        id = @machine.id ? @machine.id : "new VM"
        "QEMU/KVM (#{id})"
      end
    end
  end
end
