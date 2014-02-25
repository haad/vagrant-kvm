module VagrantPlugins
  module ProviderKvm
    module Action
      class SetMemory
        def initialize(app, env)
          @logger = Log4r::Logger.new("vagrant::action::vm::setmemory")
          @app = app
        end

        def call(env)
          memory = env[:machine].provider_config.memory

          if !memory
            memory = nil
            env[:machine].provider.driver.set_memory(nil)
          else
            # @todo Check available amount of memory
            # Memory is in KiBs so convert it.
            @logger.info("Setting number of memory to: #{memory * 1024}")
            env[:machine].provider.driver.set_memory(memory * 1024)
          end

          @app.call(env)
        end
      end
    end
  end
end
