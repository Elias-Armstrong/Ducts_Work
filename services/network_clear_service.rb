module DuctExtension
  module Services
    module NetworkClearService
      DICTIONARY = "DuctExtension"

      def self.clear_model_data(model, network = nil)
        return false unless model

        model.start_operation("Clear Duct Data", true)

        clear_entities(model.entities)

        if network
          network.clear
        else
          ::DuctExtension.network_for_model(model).clear
        end

        model.commit_operation
        true
      rescue => error
        model.abort_operation if model
        puts "NetworkClearService.clear_model_data failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.clear_entities(entities)
        entities.grep(Sketchup::Group).each do |group|
          next unless group.valid?

          if group.get_attribute(DICTIONARY, "is_duct_piece")
            group.delete_attribute(DICTIONARY)
          end

          clear_entities(group.entities)
        end
      rescue => error
        puts "NetworkClearService.clear_entities failed: #{error.message}"
      end

      private_class_method :clear_entities
    end
  end
end
