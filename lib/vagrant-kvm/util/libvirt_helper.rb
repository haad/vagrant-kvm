module VagrantPlugins
  module ProviderKvm
    module Util
      class LibvirtHelper

        # Open a connection to the qemu driver
        def self.connect
          Libvirt.open('qemu:///system')
        rescue Libvirt::Error => error
          if error.libvirt_code == 5
            # can't connect to hypervisor
            raise Errors::KvmNoConnection
          else
            raise error
          end
        end

        # Closes connection to libvirt
        def self.disconnect(conn)
          conn.close unless conn.closed?
        end

      end
    end
  end
end
