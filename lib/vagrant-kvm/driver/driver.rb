require 'libvirt'
require 'log4r'
require 'fileutils'

module VagrantPlugins
  module ProviderKvm
    module Driver
      class Driver
        # This is raised if the VM is not found when initializing
        # a driver with a UUID.
        class VMNotFound < StandardError; end

        include Util
        include Errors

        # enum for states return by libvirt
        VM_STATE = [
          :no_state,
          :running,
          :blocked,
          :paused,
          :shutdown,
          :shutoff,
          :crashed
        ]

        # The Name of the virtual machine we represent
        attr_reader :name

        # The UUID of the virtual machine we represent
        attr_reader :uuid

        # The QEMU version
        # XXX sufficient or have to check kvm and libvirt versions?
        attr_reader :version
        attr_reader :system_version

        def initialize(uuid=nil)
          @logger = Log4r::Logger.new("vagrant::provider::kvm::driver")
          @uuid = uuid
          @mac = nil
          # This should be configurable
          user=ENV['USER']||""
          @pool_name = "vagrant_#{user}"
          @network_name = "vagrant"

          # Open a connection to the qemu driver
          begin
            @conn = Libvirt::open('qemu:///system')
          rescue Libvirt::Error => e
            if e.libvirt_code == 5
              # can't connect to hypervisor
              raise Vagrant::Errors::KvmNoConnection
            else
              raise e
            end
          end

          get_system_version

          @version = read_version
          if @version < @system_version
            raise Errors::KvmInvalidVersion,
              :actual => @version, :required => @system_version
          end

          # Get storage pool if it exists
          begin
            @pool = @conn.lookup_storage_pool_by_name(@pool_name)
            @logger.info("Init storage pool #{@pool_name}")
          rescue Libvirt::RetrieveError
            # storage pool doesn't exist yet
          end

          if @uuid
            # Verify the VM exists, and if it doesn't, then don't worry
            # about it (mark the UUID as nil)
            raise VMNotFound if !vm_exists?(@uuid)
          end
        end

        def delete
          domain = @conn.lookup_domain_by_uuid(@uuid)
          definition = Util::VmDefinition.new(domain.xml_desc, 'libvirt')
          volume = @pool.lookup_volume_by_path(definition.disk)
          volume.delete
          # XXX remove pool if empty?
          @pool.refresh
          # remove any saved state
          domain.managed_save_remove if domain.has_managed_save?
          domain.undefine
        end

        # Halts the virtual machine
        def halt
          domain = @conn.lookup_domain_by_uuid(@uuid)
          domain.destroy
        end

        # Imports the VM
        #
        # @param [String] xml Path to the libvirt XML file.
        # @param [String] path Destination path for the volume.
        # @param [String] image_type An image type for the volume.
        # @param [String] qemu_bin A path of qemu binary.
        # @return [String] UUID of the imported VM.
        def import(xml, path, image_type, qemu_bin, cpu_model)
          @logger.info("Importing VM")
          # create vm definition from xml
          definition = File.open(xml) { |f|
            Util::VmDefinition.new(f.read) }
          # copy volume to storage pool
          box_disk = definition.disk
          new_disk = File.basename(box_disk, File.extname(box_disk)) + "-" +
            Time.now.to_i.to_s + ".img"

          if image_type == get_box_disk_format(old_path)
              @logger.info("Disk #{old_path} is already in requested format not converting it.")
              FileUtils.cp(old_path, tmp_path)
          else
            case image_type
            when 'qcow2'
              @logger.info("Creating volume #{new_disk} backed by #{box_disk}")
              old_path = File.join(File.dirname(xml), box_disk)
              new_path = File.join(path, new_disk)
              system("qemu-img create -f qcow2 -b #{old_path} #{new_path}")
            when 'raw'
              @logger.info("Copying volume #{box_disk} to #{new_disk}")
              old_path = File.join(File.dirname(xml), box_disk)
              new_path = File.join(path, new_disk)
              # we use qemu-img convert to preserve image size
              system("qemu-img convert #{old_path} -O #{image_type} #{new_path}")
            else
              @logger.info("Unknown Image type #{image_type}")
            end
          end

          @pool.refresh
          volume = @pool.lookup_volume_by_name(new_disk)
          definition.disk = volume.path
          definition.memory = @memory unless @memory.nil?
          definition.cpus = @vcpus unless @vcpus.nil?
          definition.mac = @mac unless @mac.nil?
          definition.name = @name
          definition.machine = get_system_machine
          definition.image_type = image_type
          definition.qemu_bin = qemu_bin unless qemu_bin.nil?
          definition.arch = cpu_model unless cpu_model.nil?
          # create vm
          @logger.info("Creating new VM")
          domain = @conn.define_domain_xml(definition.as_libvirt)
          domain.uuid
        end

        # Imports the VM from an OVF file.
        # XXX should be fusioned with import
        #
        # @param [String] ovf Path to the OVF file.
        # @param [String] path Destination path for the volume.
        # @param [String] image_type An image type for the volume.
        # @param [String] qemu_bin A path of qemu binary.
        # @return [String] UUID of the imported VM.
        def import_ovf(ovf, path, image_type, qemu_bin, cpu_model)
          @logger.info("Importing OVF definition for VM")
          # create vm definition from ovf
          definition = File.open(ovf) { |f|
            Util::VmDefinition.new(f.read, 'ovf') }

          # create volume to storage pool
          box_disk = definition.disk
          new_disk = File.basename(box_disk, File.extname(box_disk)) + "-" +
            Time.now.to_i.to_s + ".img"
          tmp_disk = File.basename(box_disk, File.extname(box_disk)) + ".img"
          # path settings
          old_path = File.join(File.dirname(ovf), box_disk)
          new_path = File.join(path, new_disk)
          tmp_path = File.join(File.dirname(ovf), tmp_disk)

          if image_type == get_box_disk_format(old_path)
              @logger.info("Disk #{old_path} is already in requested format not converting it.")
              FileUtils.cp(old_path, new_path)
          else
            case image_type
            when 'qcow2'
              unless File.file?(tmp_path)
                @logger.info("Creating native qcow2 base box image #{tmp_disk}")
                if system("qemu-img convert -p #{old_path} -c -S 16k -O #{image_type} #{tmp_path}")
                  File.unlink(old_path)
                else
                  raise Errors::KvmFailImageConversion
                end
              end
              @logger.info("Creating volume #{new_disk} backed by #{tmp_disk}")
              system("qemu-img create -f qcow2 -b #{tmp_path} #{new_path}")
            when 'raw'
              if File.file?(tmp_path)
                @logger.info("Converting volume #{tmp_disk} to #{new_disk}")
                system("qemu-img convert ${tmp_path} -O ${image_type} #{new_path}")
              else
                @logger.info("Converting volume #{old_path} to #{new_disk}")
                system("qemu-img convert ${old_path} -O ${image_type} #{new_path}")
              end
            else
              @logger.info("Unknown Image type #{image_type}")
            end
          end
          @pool.refresh
          volume = @pool.lookup_volume_by_name(new_disk)
          definition.disk = volume.path
          # Create vm

          # Add custom Settings from ProviderConfig
          definition.memory = @memory unless @memory.nil?
          definition.cpus = @vcpus unless @vcpus.nil?
          definition.set_mac(@mac) unless @mac.nil?
          definition.name = @name
          definition.disk_type = @disk_type
          definition.machine = get_system_machine
          definition.image_type = image_type
          definition.qemu_bin = qemu_bin unless qemu_bin.nil?
          definition.arch = cpu_model unless cpu_model.nil?
          definition.interface_source = @interface_source unless @interface_source.nil?
          definition.interface_type = @interface_type unless @interface_type.nil?
          definition.set_gui if @gui
          # create vm
          @logger.info("Creating new VM")
          @logger.debug("==============================")
          @logger.debug("Using VM definition\n #{definition.as_libvirt}")
          @logger.debug("==============================")
          domain = @conn.define_domain_xml(definition.as_libvirt)
          domain.uuid
        end

        # Create network
        def create_network(config)
          @logger.debug("Running create_network with #{config[:type]} -- #{config[:source]}")

          @interface_type=nil
          @interface_source=nil

          @interface_type=config[:type] if config[:type]
          @interface_source=config[:source] if config[:source]
        end

        # Initialize or create storage pool
        def init_storage(base_path)
          begin
            # Get the storage pool if it exists
            @pool = @conn.lookup_storage_pool_by_name(@pool_name)
            @logger.info("Init storage pool #{@pool_name}")
          rescue Libvirt::RetrieveError
            # Storage pool doesn't exist so we create it
            # create dir if it doesn't exist
            # if we let libvirt create the dir it is owned by root
            pool_path = base_path.join("storage-pool")
            pool_path.mkpath unless Dir.exists?(pool_path)
            storage_pool_xml = <<-EOF
          <pool type="dir">
            <name>#{@pool_name}</name>
            <target>
              <path>#{pool_path}</path>
            </target>
          </pool>
            EOF
            @pool = @conn.define_storage_pool_xml(storage_pool_xml)
            @pool.build
            @logger.info("Creating storage pool #{@pool_name} in #{pool_path}")
          end
          @pool.create unless @pool.active?
          @pool.refresh
        end

        # Returns a list of network interfaces of the VM.
        #
        # @return [Hash]
        def read_network_interfaces
          domain = @conn.lookup_domain_by_uuid(@uuid)
          Util::VmDefinition.list_interfaces(domain.xml_desc)
        end

        def read_state
          domain = @conn.lookup_domain_by_uuid(@uuid)
          state, reason = domain.state
          # check if domain has been saved
          if VM_STATE[state] == :shutoff and domain.has_managed_save?
            return :saved
          end
          VM_STATE[state]
        end

        # Return the qemu version
        #
        # @return [String] of the form "1.2.2"
        def read_version
          # libvirt returns a number like 1002002 for version 1.2.2
          maj = @conn.version / 1000000
          min = (@conn.version - maj*1000000) / 1000
          rel = @conn.version % 1000
          "#{maj}.#{min}.#{rel}"
        end

        # Returns different package version for RedHat systems and for others(Debian)
        def get_system_version
          if File.exists?("/etc/redhat-release")
            @system_version="0.1.2"
          else
            @system_version="1.2.0"
          end
        end

        def get_system_machine
          if File.exists?("/etc/redhat-release")
            @machine="pc"
          else
            @machine="pc-1.2"
          end
        end

        def get_box_disk_format(path)
          case File.extname(path)
            when '.qcow2'
              original_type='qcow2'
            when '.raw'
              original_type='raw'
            when '.img'
              original_type='img'
          end

          original_type
        end

        # Resumes the previously paused virtual machine.
        def resume
          @logger.debug("Resuming paused VM...")
          domain = @conn.lookup_domain_by_uuid(@uuid)
          domain.resume
          true
        end

        def set_name(name)
          @name = name
        end

        def set_vcpus(vcpus)
          @vcpus = vcpus
        end

        def set_memory(memory)
           @memory = memory
        end

        def set_disk_type(disk_type)
          @disk_type = disk_type
        end

        def set_mac_address(mac)
#          domain = @conn.lookup_domain_by_uuid(@uuid)
#          definition = Util::VmDefinition.new(domain.xml_desc, 'libvirt')
#          definition.set_mac(mac)
#          domain.undefine
#          @conn.define_domain_xml(definition.as_libvirt)
            @mac = mac
        end

        def set_gui
            @gui = true
        end

        # Starts the virtual machine.
        def start
          @logger.debug("Booting domain with uuid: #{@uuid}")
          domain = @conn.lookup_domain_by_uuid(@uuid)
          domain.create
          true
        end

        # Suspend the virtual machine and saves its states.
        def suspend
          domain = @conn.lookup_domain_by_uuid(@uuid)
          domain.managed_save
        end

        # Verifies that the driver is ready and the connection is open
        #
        # This will raise a VagrantError if things are not ready.
        def verify!
          if @conn.closed?
            raise Errors::KvmNoConnection
          end
        end

        # Checks if a VM with the given UUID exists.
        #
        # @return [Boolean]
        def vm_exists?(uuid)
          begin
            @logger.info("Check if VM #{uuid} exists")
            @conn.lookup_domain_by_uuid(uuid)
          rescue Libvirt::RetrieveError
            false
          end
        end
      end
    end
  end
end
