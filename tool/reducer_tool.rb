# ===== Consolidated from: tool/reducer_prompt.rb =====
module DuctExtension
  module Tool
    # One prompt implementation for both DuctTool's End Reducer mode and the
    # standalone ReducerTool. The last-used values are shared intentionally.
    module ReducerPrompt
      @last_round_diameter = 10.0
      @last_rectangular_width = 16.0
      @last_rectangular_height = 10.0
      @last_length = 0.0

      class << self
        def prompt_for_port(port)
          dimensions = Model::Port.dimensions_from_params({}, port)

          if Catalog::Manager.active?(Sketchup.active_model)
            selection = Catalog::Manager.prompt_transition_target(
              dimensions,
              title: "#{Catalog::Manager.active_name(@model)} Increaser / Reducer",
              model: Sketchup.active_model
            )
            return nil unless selection

            target = Model::DuctDimensions.coerce(selection[:dimensions])
            return {
              shape: target[:shape],
              diameter: target[:diameter],
              width: target[:width],
              height: target[:height],
              length: selection[:length]
            }
          end

          dimensions[:shape] == :rectangular ? prompt_rectangular(dimensions) : prompt_round(dimensions)
        end

        private

        def prompt_round(dimensions)
          default_length = Geometry::ReducerBuilder.default_length(
            dimensions,
            { shape: :round, diameter: @last_round_diameter }
          )

          input = ::UI.inputbox(
            ["Current Diameter:", "New Diameter:", "Transition Length:"],
            [dimensions[:diameter].to_s, @last_round_diameter.to_s, length_default(default_length)],
            [],
            "Round Increaser / Reducer"
          )
          return nil unless input

          diameter = InputHelpers.positive_number(input[1])
          length = InputHelpers.positive_number(input[2], 0.0)
          return invalid("Please enter a valid new diameter.") unless diameter
          return invalid("The new diameter must be different from the current diameter.") if
            (diameter - dimensions[:diameter].to_f).abs <= 0.001

          @last_round_diameter = diameter
          @last_length = length
          { shape: :round, diameter: diameter, width: diameter, height: diameter, length: length }
        end

        def prompt_rectangular(dimensions)
          default_length = Geometry::ReducerBuilder.default_length(
            dimensions,
            {
              shape: :rectangular,
              width: @last_rectangular_width,
              height: @last_rectangular_height
            }
          )

          input = ::UI.inputbox(
            ["Current Width:", "Current Height:", "New Width:", "New Height:", "Transition Length:"],
            [
              dimensions[:width].to_s,
              dimensions[:height].to_s,
              @last_rectangular_width.to_s,
              @last_rectangular_height.to_s,
              length_default(default_length)
            ],
            [],
            "Rectangular Increaser / Reducer"
          )
          return nil unless input

          width = InputHelpers.positive_number(input[2])
          height = InputHelpers.positive_number(input[3])
          length = InputHelpers.positive_number(input[4], 0.0)
          return invalid("Please enter a valid new width and height.") unless width && height

          changed =
            (width - dimensions[:width].to_f).abs > 0.001 ||
            (height - dimensions[:height].to_f).abs > 0.001
          return invalid("The new width or height must be different from the current size.") unless changed

          @last_rectangular_width = width
          @last_rectangular_height = height
          @last_length = length
          { shape: :rectangular, diameter: [width, height].max, width: width, height: height, length: length }
        end

        def length_default(default_length)
          @last_length.to_f > 0.0 ? @last_length.to_s : default_length.round(2).to_s
        end

        def invalid(message)
          ::UI.messagebox(message)
          nil
        end
      end
    end
  end
end

# ===== Consolidated from: tool/reducer_tool.rb =====
module DuctExtension
  module Tool
    class ReducerTool

      def initialize
        @network = ::DuctExtension.network_for_model(Sketchup.active_model)
        @current_ip = Sketchup::InputPoint.new
      end

      def activate
        @network = Services::NetworkRebuildService.rebuild(Sketchup.active_model)

        Sketchup.status_text =
          "Add Increaser / Reducer: click an open duct end, then enter the new size."
      end

      def onMouseMove(flags, x, y, view)
        @current_ip.pick(view, x, y)
        view.invalidate if view
      rescue => error
        puts "ReducerTool.onMouseMove failed: #{error.message}"
      end

      def draw(view)
        return unless @current_ip && @current_ip.valid?

        @current_ip.draw(view)
      rescue => error
        puts "ReducerTool.draw failed: #{error.message}"
      end

      def onLButtonDown(flags, x, y, view)
        ip = Sketchup::InputPoint.new
        ip.pick(view, x, y)

        point = ip.position
        return unless point

        snap = Services::SnapService.find_open_external_port(
          network: @network,
          view: view,
          x: x,
          y: y,
          point: point
        )

        port = snap&.port

        unless port
          UI.messagebox("Increaser / Reducer: click an open duct end.")
          return
        end

        input = ReducerPrompt.prompt_for_port(port)
        return unless input

        result = Services::EndReducerInsertService.insert_at_port(
          model: Sketchup.active_model,
          network: @network,
          stem_port: port,
          new_shape: input[:shape],
          new_diameter: input[:diameter],
          new_width: input[:width],
          new_height: input[:height],
          length: input[:length]
        )

        if result
          @network.rebuild_index! if @network.respond_to?(:rebuild_index!)

          Sketchup.status_text =
            "Increaser / reducer inserted. Use Draw Orthogonal Duct and click the new open end to continue."

          view.invalidate if view
        else
          UI.messagebox("Could not insert increaser / reducer here.")
        end
      rescue => error
        puts "ReducerTool.onLButtonDown failed: #{error.message}"
        puts error.backtrace.join("\n")
        UI.messagebox("Could not insert increaser / reducer. Check the Ruby Console for details.")
      end

      def onCancel(reason, view)
        Sketchup.active_model.select_tool(nil)
      end

    end
  end
end
