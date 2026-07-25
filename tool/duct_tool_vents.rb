module DuctExtension
  module Tool
    module DuctToolVents
      private

      def handle_vent_click(view, x, y, clicked_point)
        pipe_piece = Services::SnapService.picked_pipe_piece(
          network: @network,
          view: view,
          x: x,
          y: y
        )

        pipe_piece ||= nearest_pipe_piece_for_vent_click(clicked_point)

        unless pipe_piece
          ::UI.messagebox("Add Vent mode: click an existing duct pipe. Click near the end for an end cover, or click the side for a register.")
          return
        end

        unless pipe_piece.ports && pipe_piece.ports.length >= 2
          ::UI.messagebox("Add Vent mode: vents can be placed on duct pipes.")
          return
        end

        dimensions = Model::Port.dimensions_from_params({}, pipe_piece.ports.first)
        input = prompt_for_vent(dimensions)
        return unless input

        result = Services::VentInsertService.insert_on_piece(
          model: Sketchup.active_model,
          network: @network,
          duct_piece: pipe_piece,
          click_point: clicked_point,
          register_width: input[:register_width],
          register_height: input[:register_height],
          register_bumped_out: input[:register_bumped_out],
          cover_diameter: input[:cover_diameter],
          cover_width: input[:cover_width],
          cover_height: input[:cover_height],
          repeat_enabled: duct_tool_class_setting(:@@vent_repeat_enabled),
          repeat_direction: duct_tool_class_setting(:@@vent_repeat_direction),
          repeat_interval: duct_tool_class_setting(:@@vent_repeat_interval),
          view: view
        )

        if result
          @last_port = nil
          @start_point = nil
          @orthogonal_axis_lock = nil
          @fitting_mode = :vent

          if result[:vent_type] == :side_register_repeat
            Sketchup.status_text = "#{result[:count]} vents inserted. Still in Add Vent mode."
          else
            Sketchup.status_text = "Vent inserted. Still in Add Vent mode: click another pipe end or side."
          end
        else
          ::UI.messagebox("Could not insert vent here. Try clicking closer to the side or end of a duct pipe.")
        end
      rescue => error
        puts "DuctTool.handle_vent_click failed: #{error.message}"
        puts error.backtrace.join("\n")
        ::UI.messagebox("Could not insert vent. Check the Ruby Console for details.")
      end

      def nearest_pipe_piece_for_vent_click(clicked_point)
        return nil unless @network && @network.respond_to?(:pieces)

        best_piece = nil
        best_distance = nil

        @network.pieces.each do |piece|
          next unless piece
          next unless piece.type == :pipe
          next unless piece.group && piece.group.valid?
          next unless piece.ports && piece.ports.length >= 2

          port_a = piece.ports[0]
          port_b = piece.ports[1]
          next unless port_a && port_b && port_a.point && port_b.point

          closest = closest_point_on_segment_for_vent(
            port_a.point,
            port_b.point,
            clicked_point
          )
          next unless closest

          distance = closest.distance(clicked_point)
          dimensions = Model::Port.dimensions_from_params({}, port_a)

          tolerance = [
            dimensions[:diameter].to_f,
            dimensions[:width].to_f,
            dimensions[:height].to_f,
            6.0
          ].max * 1.8

          next if distance > tolerance

          if best_distance.nil? || distance < best_distance
            best_distance = distance
            best_piece = piece
          end
        end

        best_piece
      rescue => error
        puts "DuctTool.nearest_pipe_piece_for_vent_click failed: #{error.message}"
        nil
      end

      def closest_point_on_segment_for_vent(start_point, end_point, point)
        axis = start_point.vector_to(end_point)
        return nil if axis.length <= 0.0

        length = axis.length
        axis.normalize!

        amount = start_point.vector_to(point).dot(axis)
        amount = [[amount, 0.0].max, length].min

        start_point.offset(axis, amount)
      rescue
        nil
      end

      def prompt_for_vent(dimensions)
        dimensions[:shape] == :rectangular ? prompt_for_rectangular_vent(dimensions) : prompt_for_round_vent(dimensions)
      end

      def prompt_for_round_vent(dimensions)
        diameter = dimensions[:diameter].to_f

        input = ::UI.inputbox(
          [
            "Side Register Plate Width:",
            "Side Register Plate Height:",
            "Register Bumped Out?",
            "End Cover Diameter:"
          ],
          [
            InputHelpers.format_number(diameter * 1.35),
            InputHelpers.format_number(diameter * 0.55),
            "Yes",
            InputHelpers.format_number(diameter * 1.22)
          ],
          ["", "", "Yes|No", ""],
          "Round Duct Vent"
        )

        return nil unless input

        {
          register_width: InputHelpers.positive_number(input[0], diameter * 1.35),
          register_height: InputHelpers.positive_number(input[1], diameter * 0.55),
          register_bumped_out: InputHelpers.yes?(input[2]),
          cover_diameter: InputHelpers.positive_number(input[3], diameter * 1.22),
          cover_width: nil,
          cover_height: nil
        }
      end

      def prompt_for_rectangular_vent(dimensions)
        width = dimensions[:width].to_f
        height = dimensions[:height].to_f
        largest = [width, height].max

        input = ::UI.inputbox(
          [
            "Side Register Plate Width:",
            "Side Register Plate Height:",
            "Register Bumped Out?",
            "End Cover Width:",
            "End Cover Height:"
          ],
          [
            InputHelpers.format_number(largest * 1.10),
            InputHelpers.format_number(largest * 0.45),
            "Yes",
            InputHelpers.format_number(width * 1.22),
            InputHelpers.format_number(height * 1.22)
          ],
          ["", "", "Yes|No", "", ""],
          "Rectangular Duct Vent"
        )

        return nil unless input

        {
          register_width: InputHelpers.positive_number(input[0], largest * 1.10),
          register_height: InputHelpers.positive_number(input[1], largest * 0.45),
          register_bumped_out: InputHelpers.yes?(input[2]),
          cover_diameter: nil,
          cover_width: InputHelpers.positive_number(input[3], width * 1.22),
          cover_height: InputHelpers.positive_number(input[4], height * 1.22)
        }
      end

    end
  end
end
