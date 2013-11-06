module VagrantPlugins
  module ProviderKvm
    module Action
      class SetVCpu
        def initialize(app, env)
          @logger = Log4r::Logger.new("vagrant::action::vm::setvcpu")
          @app = app
        end

        def call(env)
          vcpus = env[:machine].provider_config.cpus

          if !vcpus
            vcpus = nil
          end

          # @todo check number of vcpus

          @logger.info("Setting number of vcpus used to: #{vcpus}")
          env[:machine].provider.driver.set_vcpus(vcpus)

          @app.call(env)
        end

      end
    end
  end
end
