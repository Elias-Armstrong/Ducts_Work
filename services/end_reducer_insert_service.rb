module DuctExtension
  module Services
    class EndReducerInsertService
      def self.insert_at_port(
        model:,
        network:,
        stem_port:,
        new_diameter: nil,
        new_width: nil,
        new_height: nil,
        length: nil
      )
        return nil unless model && network && stem_port
        return nil unless stem_port.piece && stem_port.piece.group && stem_port.piece.group.valid?

        start_dimensions = Model::Port.dimensions_from_params({}, stem_port)
        end_dimensions = requested_dimensions(
          stem_port,
          start_dimensions,
          new_diameter: new_diameter,
          new_width: new_width,
          new_height: new_height
        )
        return nil unless valid_size_change?(start_dimensions, end_dimensions)

        ModelOperation.run(
          model: model,
          network: network,
          name: "Insert Increaser / Reducer"
        ) do |operation|
          transition = BranchTransitionService.attach(
            model: model,
            network: network,
            source_port: stem_port,
            target_dimensions: end_dimensions,
            preferred_width_axis: stem_port.width_axis,
            preferred_height_axis: stem_port.height_axis,
            cap_output: true,
            length: length
          )
          operation.abort!(nil) unless transition && transition[:piece]

          {
            piece: transition[:piece],
            old_port: transition[:input_port],
            new_port: transition[:output_port],
            start_dimensions: start_dimensions,
            end_dimensions: end_dimensions
          }
        end
      rescue => error
        puts "EndReducerInsertService.insert_at_port failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.requested_dimensions(stem_port, start_dimensions, new_diameter:, new_width:, new_height:)
        params =
          if start_dimensions[:shape] == :rectangular
            { shape: :rectangular, width: new_width, height: new_height }
          else
            { shape: :round, diameter: new_diameter }
          end

        Model::Port.dimensions_from_params(params, stem_port)
      end
      private_class_method :requested_dimensions

      def self.valid_size_change?(start_dimensions, end_dimensions)
        return false unless start_dimensions && end_dimensions
        return false unless start_dimensions[:shape] == end_dimensions[:shape]

        BranchTransitionService.transition_needed?(start_dimensions, end_dimensions)
      rescue
        false
      end
    end
  end
end
