module DuctExtension
  module Services
    module NetworkClearService
      DICTIONARY = "DuctExtension"

      def self.clear_model_data(model, network = nil)
        return false unless model

        target_network = network || ::DuctExtension.network_for_model(model)

        ModelOperation.run(
          model: model,
          network: target_network,
          name: "Clear Duct Data",
          rebuild_on_failure: true
        ) do
          clear_entities(model.entities)
          target_network.clear
          true
        end
      rescue => error
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
