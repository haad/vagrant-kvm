module VagrantPlugins
  module ProviderKvm
    module Action
      class SetDiskType
        def initialize(app, env)
          @logger = Log4r::Logger.new("vagrant::action::vm::setdisktype")
          @app = app
        end

        def call(env)
          disk_type = env[:machine].provider_config.disk_type.to_sym

          if !disk_type
            disk_type = :virtio
          end

          @logger.info("Setting VM disk type to : #{disk_type}")
          env[:machine].provider.driver.set_disk_type(disk_type)

          @app.call(env)
        end
      end
    end
  end
end
