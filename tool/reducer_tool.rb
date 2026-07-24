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
