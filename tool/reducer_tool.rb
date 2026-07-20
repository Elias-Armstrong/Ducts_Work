module DuctExtension
  module Tool
    class ReducerTool
      @@last_round_diameter = 10.0
      @@last_rectangular_width = 16.0
      @@last_rectangular_height = 10.0
      @@last_length = 0.0

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

        input = prompt_for_new_size(port)
        return unless input

        result = Services::EndReducerInsertService.insert_at_port(
          model: Sketchup.active_model,
          network: @network,
          stem_port: port,
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

      private

      def prompt_for_new_size(port)
        dimensions = Model::Port.dimensions_from_params({}, port)

        if dimensions[:shape] == :rectangular
          prompt_for_rectangular_size(dimensions)
        else
          prompt_for_round_size(dimensions)
        end
      end

      def prompt_for_round_size(dimensions)
        default_length = Geometry::ReducerBuilder.default_length(
          dimensions,
          {
            shape: :round,
            diameter: @@last_round_diameter
          }
        )

        prompts = [
          "Current Diameter:",
          "New Diameter:",
          "Transition Length:"
        ]

        defaults = [
          dimensions[:diameter].to_s,
          @@last_round_diameter.to_s,
          length_default(default_length)
        ]

        input = UI.inputbox(
          prompts,
          defaults,
          [],
          "Round Increaser / Reducer"
        )

        return nil unless input

        new_diameter = positive_number(input[1], nil)
        length = positive_number(input[2], 0.0)

        unless new_diameter
          UI.messagebox("Please enter a valid new diameter.")
          return nil
        end

        if (new_diameter - dimensions[:diameter].to_f).abs <= 0.001
          UI.messagebox("The new diameter must be different from the current diameter.")
          return nil
        end

        @@last_round_diameter = new_diameter
        @@last_length = length

        {
          diameter: new_diameter,
          width: new_diameter,
          height: new_diameter,
          length: length
        }
      end

      def prompt_for_rectangular_size(dimensions)
        default_length = Geometry::ReducerBuilder.default_length(
          dimensions,
          {
            shape: :rectangular,
            width: @@last_rectangular_width,
            height: @@last_rectangular_height
          }
        )

        prompts = [
          "Current Width:",
          "Current Height:",
          "New Width:",
          "New Height:",
          "Transition Length:"
        ]

        defaults = [
          dimensions[:width].to_s,
          dimensions[:height].to_s,
          @@last_rectangular_width.to_s,
          @@last_rectangular_height.to_s,
          length_default(default_length)
        ]

        input = UI.inputbox(
          prompts,
          defaults,
          [],
          "Rectangular Increaser / Reducer"
        )

        return nil unless input

        new_width = positive_number(input[2], nil)
        new_height = positive_number(input[3], nil)
        length = positive_number(input[4], 0.0)

        unless new_width && new_height
          UI.messagebox("Please enter a valid new width and height.")
          return nil
        end

        width_changed = (new_width - dimensions[:width].to_f).abs > 0.001
        height_changed = (new_height - dimensions[:height].to_f).abs > 0.001

        unless width_changed || height_changed
          UI.messagebox("The new width or height must be different from the current size.")
          return nil
        end

        @@last_rectangular_width = new_width
        @@last_rectangular_height = new_height
        @@last_length = length

        {
          diameter: [new_width, new_height].max,
          width: new_width,
          height: new_height,
          length: length
        }
      end

      def length_default(default_length)
        if @@last_length && @@last_length.to_f > 0.0
          @@last_length.to_s
        else
          default_length.round(2).to_s
        end
      end

      def positive_number(value, fallback)
        number = value.to_f
        number > 0.0 ? number : fallback
      rescue
        fallback
      end
    end
  end
end
