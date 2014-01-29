module VagrantPlugins
  module ProviderKvm
    module Action
      class PrepareNFSSettings
        def initialize(app,env)
          @app = app
          @logger = Log4r::Logger.new("vagrant::action::vm::nfs")
        end

        def call(env)
          @app.call(env)
          @env = env

          using_nfs = false
          env[:machine].config.vm.synced_folders.each do |id, opts|
            if opts[:nfs]
              using_nfs = true
              break
            end
          end

          if using_nfs
            @logger.info("Using NFS, preparing NFS settings by reading host IP and machine IP")
            env[:nfs_host_ip]    = read_host_ip(env[:machine])
            env[:nfs_machine_ip] = read_machine_ip(env[:machine])

            raise Vagrant::Errors::NFSNoHostonlyNetwork if !env[:nfs_machine_ip]
          end
        end

        # Returns the IP address of the first host only network adapter
        #
        # @param [Machine] machine
        # @return [String]
        def read_host_ip(machine)
          ip = read_machine_ip(machine)
          if ip
            base_ip = ip.split(".")
            base_ip[3] = "1"
            return base_ip.join(".")
          end

          nil
        end

        # Returns the IP address of the guest by looking at the first
        # enabled host only network.
        #
        # @return [String]
        def read_machine_ip(machine)
          conn = Util::LibvirtHelper.connect
          xml = conn.lookup_domain_by_uuid(@env[:machine].id).xml_desc
          xml =~ /<mac address='(.+)'\/>/
          mac = $1
          line = ''
          180.times do
            arp = `arp -n`.split("\n")
            line = arp.detect { |l| l.include?(mac) }
            line ? break : sleep(1)
          end
          line =~ /(\d+\.\d+\.\d+\.\d+)/
          Util::LibvirtHelper.disconnect(conn)

          $1
        end
      end
    end
  end
end
