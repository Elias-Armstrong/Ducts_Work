module DuctExtension
  module Services
    class VentInsertService
      EPSILON = 0.000001

      DEFAULT_REGISTER_WIDTH_FACTOR = 1.35
      DEFAULT_REGISTER_HEIGHT_FACTOR = 0.55
      DEFAULT_END_COVER_FACTOR = 1.22

      END_CLICK_DISTANCE_FACTOR = 1.65
      END_CLICK_MAX_DISTANCE = 18.0

      def self.insert_on_piece(
        model:,
        network:,
        duct_piece:,
        click_point:,
        register_width: nil,
        register_height: nil,
        register_bumped_out: true,
        cover_diameter: nil,
        cover_width: nil,
        cover_height: nil,
        repeat_enabled: false,
        repeat_direction: :right,
        repeat_interval: 24.0,
        view: nil
      )
        return nil unless model && duct_piece
        return nil unless duct_piece.group && duct_piece.group.valid?
        return nil unless duct_piece.ports && duct_piece.ports.length >= 2

        click_point = Geometry::RectangularFrame.point3d(click_point)
        return nil unless click_point

        dimensions = Model::Port.dimensions_from_params({}, duct_piece.ports.first)

        port_a = duct_piece.ports[0]
        port_b = duct_piece.ports[1]

        axis = port_a.point.vector_to(port_b.point)
        return nil if axis.length <= EPSILON
        axis.normalize!

        end_port = clicked_end_port(
          network: network,
          ports: [port_a, port_b],
          click_point: click_point,
          dimensions: dimensions
        )

        catalog_terminal_product = nil
        catalog_side_product = nil
        if Catalog::Manager.active?(model)
          if end_port
            terminal_products =
              Catalog::Manager.end_cover_products(dimensions, model) +
              Catalog::Manager.register_box_products(dimensions, model) +
              Catalog::Manager.wall_vent_products(dimensions, model) +
              Catalog::Manager.fresh_air_vent_products(dimensions, model)
            return Catalog::Manager.notify_unsupported(:vent, dimensions) if terminal_products.empty?
            catalog_terminal_product = Catalog::Manager.prompt_terminal_product(dimensions, model)
            return nil unless catalog_terminal_product
          else
            side_products = Catalog::Manager.register_box_saddle_products(dimensions, model)
            return Catalog::Manager.notify_unsupported(:register_box_saddle, dimensions) if side_products.empty?
            catalog_side_product = Catalog::Manager.prompt_register_box_saddle(dimensions, model)
            return nil unless catalog_side_product
          end
        end

        ModelOperation.run(
          model: model,
          network: network,
          name: "Insert Duct Vent"
        ) do |operation|

        result =
          if end_port && catalog_terminal_product && catalog_terminal_product.family == :fresh_air_vent
            insert_catalog_fresh_air_vent(
              model: model,
              duct_piece: duct_piece,
              end_port: end_port,
              dimensions: dimensions,
              catalog_product: catalog_terminal_product
            )
          elsif end_port && catalog_terminal_product && catalog_terminal_product.family == :wall_vent
            insert_catalog_wall_vent(
              model: model,
              duct_piece: duct_piece,
              end_port: end_port,
              dimensions: dimensions,
              catalog_product: catalog_terminal_product
            )
          elsif end_port && catalog_terminal_product && catalog_terminal_product.family == :register_box
            insert_catalog_register_box(
              model: model,
              duct_piece: duct_piece,
              end_port: end_port,
              dimensions: dimensions,
              catalog_product: catalog_terminal_product
            )
          elsif end_port
            insert_end_cover(
              model: model,
              duct_piece: duct_piece,
              end_port: end_port,
              dimensions: dimensions,
              cover_diameter: cover_diameter,
              cover_width: cover_width,
              cover_height: cover_height,
              catalog_product: catalog_terminal_product
            )
          elsif repeat_enabled && repeat_interval.to_f > EPSILON
            insert_repeated_side_registers(
              model: model,
              duct_piece: duct_piece,
              click_point: click_point,
              dimensions: dimensions,
              register_width: register_width,
              register_height: register_height,
              register_bumped_out: register_bumped_out,
              repeat_direction: repeat_direction,
              repeat_interval: repeat_interval,
              view: view,
              catalog_product: catalog_side_product
            )
          else
            insert_side_register(
              model: model,
              duct_piece: duct_piece,
              click_point: click_point,
              dimensions: dimensions,
              register_width: register_width,
              register_height: register_height,
              register_bumped_out: register_bumped_out,
              catalog_product: catalog_side_product
            )
          end

          operation.abort!(nil) unless result
          result
        end
      rescue => error
        puts "VentInsertService.insert_on_piece failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.insert_end_cover(
        model:,
        duct_piece:,
        end_port:,
        dimensions:,
        cover_diameter: nil,
        cover_width: nil,
        cover_height: nil,
        catalog_product: nil
      )
        catalog_product ||= Catalog::Manager.end_cover_product(dimensions, model) if Catalog::Manager.active?(model)

        group = model.active_entities.add_group
        group.name =
          if catalog_product
            "#{Catalog::Manager.product_catalog_name(catalog_product)} #{catalog_product.sku} — Duct Cap"
          elsif dimensions[:shape] == :rectangular
            "Rectangular End Vent Cover"
          else
            "Round End Vent Cover"
          end

        outward_axis = end_port.vector.clone
        outward_axis.normalize!

        success =
          if dimensions[:shape] == :rectangular
            width_axis = end_port.width_axis
            height_axis = end_port.height_axis

            basis = Geometry::RectangularFrame.stable_basis_for_axis(
              outward_axis,
              dimensions[:width],
              dimensions[:height],
              preferred_width_axis: width_axis,
              preferred_height_axis: height_axis,
              allow_relevel: false
            )

            width_axis = basis && basis[:width_axis]
            height_axis = basis && basis[:height_axis]

            if catalog_product
              Catalog::MasterFlowGeometry.build_stack_cap(
                group: group,
                center: end_port.point,
                axis: outward_axis,
                product: catalog_product,
                preferred_width_axis: width_axis,
                preferred_height_axis: height_axis
              )
            else
              Geometry::VentBuilder.build_rectangular_end_cover_into(
                group,
                center: end_port.point,
                axis: outward_axis,
                width: dimensions[:width],
                height: dimensions[:height],
                width_axis: width_axis,
                height_axis: height_axis,
                cover_width: cover_width,
                cover_height: cover_height
              )
            end
          else
            if catalog_product
              Catalog::MasterFlowGeometry.build_round_cap(
                group: group,
                center: end_port.point,
                axis: outward_axis,
                product: catalog_product
              )
            else
              Geometry::VentBuilder.build_round_end_cover_into(
                group,
                center: end_port.point,
                axis: outward_axis,
                duct_diameter: dimensions[:diameter],
                cover_diameter: cover_diameter
              )
            end
          end

        unless success
          group.erase! if group.valid?
          return nil
        end

        Catalog::Manager.apply_product_metadata(group, catalog_product) if catalog_product

        {
          group: group,
          vent_type: :end_cover,
          dimensions: dimensions,
          end_port: end_port
        }
      rescue => error
        puts "VentInsertService.insert_end_cover failed: #{error.message}"
        puts error.backtrace.join("\n")
        group.erase! if group && group.valid?
        nil
      end

      def self.insert_catalog_fresh_air_vent(model:, duct_piece:, end_port:, dimensions:, catalog_product:)
        return nil unless catalog_product && catalog_product.family == :fresh_air_vent

        group = model.active_entities.add_group
        group.name = "#{Catalog::Manager.product_catalog_name(catalog_product)} #{catalog_product.sku} — Fresh Air Vent"
        outward_axis = end_port.vector.clone
        outward_axis.normalize!

        success = Catalog::MasterFlowGeometry.build_fresh_air_vent(
          group: group,
          center: end_port.point,
          axis: outward_axis,
          product: catalog_product,
          preferred_width_axis: end_port.respond_to?(:width_axis) ? end_port.width_axis : nil,
          preferred_height_axis: end_port.respond_to?(:height_axis) ? end_port.height_axis : nil
        )
        unless success
          group.erase! if group.valid?
          return nil
        end

        Catalog::Manager.apply_product_metadata(group, catalog_product)
        {
          group: group,
          vent_type: :catalog_fresh_air_vent,
          dimensions: dimensions,
          end_port: end_port,
          product: catalog_product
        }
      rescue => error
        puts "VentInsertService.insert_catalog_fresh_air_vent failed: #{error.message}"
        puts error.backtrace.join("\n") if error.backtrace
        group.erase! if group && group.valid?
        nil
      end

      def self.insert_catalog_wall_vent(model:, duct_piece:, end_port:, dimensions:, catalog_product:)
        return nil unless catalog_product && catalog_product.family == :wall_vent

        group = model.active_entities.add_group
        group.name = "#{Catalog::Manager.product_catalog_name(catalog_product)} #{catalog_product.sku} — Appliance Wall Vent"
        outward_axis = end_port.vector.clone
        outward_axis.normalize!

        success = Catalog::MasterFlowGeometry.build_wall_vent(
          group: group,
          center: end_port.point,
          axis: outward_axis,
          product: catalog_product,
          preferred_width_axis: end_port.respond_to?(:width_axis) ? end_port.width_axis : nil,
          preferred_height_axis: end_port.respond_to?(:height_axis) ? end_port.height_axis : nil
        )
        unless success
          group.erase! if group.valid?
          return nil
        end

        Catalog::Manager.apply_product_metadata(group, catalog_product)
        {
          group: group,
          vent_type: :catalog_wall_vent,
          dimensions: dimensions,
          end_port: end_port,
          product: catalog_product
        }
      rescue => error
        puts "VentInsertService.insert_catalog_wall_vent failed: #{error.message}"
        puts error.backtrace.join("\n") if error.backtrace
        group.erase! if group && group.valid?
        nil
      end

      def self.insert_catalog_register_box(model:, duct_piece:, end_port:, dimensions:, catalog_product:)
        return nil unless catalog_product && catalog_product.family == :register_box
        return nil unless dimensions[:shape] == :round

        group = model.active_entities.add_group
        group.name = "#{Catalog::Manager.product_catalog_name(catalog_product)} #{catalog_product.sku} — Register Box"
        outward_axis = end_port.vector.clone
        outward_axis.normalize!

        success = Catalog::MasterFlowGeometry.build_register_box(
          group: group,
          center: end_port.point,
          axis: outward_axis,
          product: catalog_product
        )
        unless success
          group.erase! if group.valid?
          return nil
        end

        Catalog::Manager.apply_product_metadata(group, catalog_product)
        {
          group: group,
          vent_type: :catalog_register_box,
          dimensions: dimensions,
          end_port: end_port,
          product: catalog_product
        }
      rescue => error
        puts "VentInsertService.insert_catalog_register_box failed: #{error.message}"
        puts error.backtrace.join("\n") if error.backtrace
        group.erase! if group && group.valid?
        nil
      end

      def self.insert_side_register(
        model:,
        duct_piece:,
        click_point:,
        dimensions:,
        register_width: nil,
        register_height: nil,
        register_bumped_out: true,
        catalog_product: nil
      )
        placement = side_register_placement(
          duct_piece: duct_piece,
          click_point: click_point,
          dimensions: dimensions
        )
        return nil unless placement

        insert_side_register_at_axis_point(
          model: model,
          duct_piece: duct_piece,
          dimensions: dimensions,
          axis_point: placement[:axis_point],
          outward_axis: placement[:outward_axis],
          axis: placement[:axis],
          register_width: register_width,
          register_height: register_height,
          register_bumped_out: register_bumped_out,
          catalog_product: catalog_product
        )
      rescue => error
        puts "VentInsertService.insert_side_register failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.insert_repeated_side_registers(
        model:,
        duct_piece:,
        click_point:,
        dimensions:,
        register_width: nil,
        register_height: nil,
        register_bumped_out: true,
        repeat_direction: :right,
        repeat_interval: 24.0,
        view: nil,
        catalog_product: nil
      )
        port_a = duct_piece.ports[0]
        port_b = duct_piece.ports[1]

        axis = port_a.point.vector_to(port_b.point)
        return nil if axis.length <= EPSILON

        length = axis.length
        axis.normalize!

        placement = side_register_placement(
          duct_piece: duct_piece,
          click_point: click_point,
          dimensions: dimensions
        )
        return nil unless placement

        start_amount = port_a.point.vector_to(placement[:axis_point]).dot(axis)
        start_amount = [[start_amount, 0.0].max, length].min

        step_sign = repeat_step_sign(
          port_a: port_a,
          port_b: port_b,
          repeat_direction: repeat_direction,
          view: view
        )

        interval = repeat_interval.to_f.abs
        return nil if interval <= EPSILON

        amounts = []
        current = start_amount

        loop_guard = 0
        while current >= -EPSILON && current <= length + EPSILON && loop_guard < 500
          amounts << [[current, 0.0].max, length].min
          current += step_sign * interval
          loop_guard += 1
        end

        amounts = unique_amounts(amounts)
        return nil if amounts.empty?

        results = []

        amounts.each do |amount|
          axis_point = port_a.point.offset(axis, amount)

          inserted = insert_side_register_at_axis_point(
            model: model,
            duct_piece: duct_piece,
            dimensions: dimensions,
            axis_point: axis_point,
            outward_axis: placement[:outward_axis],
            axis: axis,
            register_width: register_width,
            register_height: register_height,
            register_bumped_out: register_bumped_out,
            catalog_product: catalog_product
          )

          results << inserted if inserted
        end

        return nil if results.empty?

        {
          group: results.first[:group],
          groups: results.map { |result| result[:group] },
          vent_type: :side_register_repeat,
          dimensions: dimensions,
          base_center: results.first[:base_center],
          outward_axis: placement[:outward_axis],
          count: results.length,
          interval: interval,
          direction: repeat_direction
        }
      rescue => error
        puts "VentInsertService.insert_repeated_side_registers failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.side_register_placement(duct_piece:, click_point:, dimensions:)
        port_a = duct_piece.ports[0]
        port_b = duct_piece.ports[1]

        axis = port_a.point.vector_to(port_b.point)
        return nil if axis.length <= EPSILON
        axis.normalize!

        closest = closest_point_on_piece_axis(port_a.point, port_b.point, click_point)
        return nil unless closest

        outward_axis =
          if dimensions[:shape] == :rectangular
            rectangular_outward_axis(
              port: port_a,
              axis: axis,
              center_point: closest,
              click_point: click_point
            )
          else
            round_outward_axis(
              axis: axis,
              center_point: closest,
              click_point: click_point
            )
          end

        return nil unless outward_axis

        {
          axis: axis,
          axis_point: closest,
          outward_axis: outward_axis
        }
      rescue => error
        puts "VentInsertService.side_register_placement failed: #{error.message}"
        nil
      end

      def self.insert_side_register_at_axis_point(
        model:,
        duct_piece:,
        dimensions:,
        axis_point:,
        outward_axis:,
        axis:,
        register_width: nil,
        register_height: nil,
        register_bumped_out: true,
        catalog_product: nil
      )
        port_a = duct_piece.ports[0]

        base_center =
          if dimensions[:shape] == :rectangular
            rectangular_surface_center(
              port: port_a,
              axis: axis,
              center_point: axis_point,
              outward_axis: outward_axis,
              dimensions: dimensions
            )
          else
            axis_point.offset(outward_axis, dimensions[:diameter].to_f / 2.0)
          end

        largest = Model::DuctDimensions.coerce(dimensions).largest

        plate_width = register_width.to_f
        plate_height = register_height.to_f

        plate_width = largest * DEFAULT_REGISTER_WIDTH_FACTOR if plate_width <= 0.0
        plate_height = largest * DEFAULT_REGISTER_HEIGHT_FACTOR if plate_height <= 0.0

        group = model.active_entities.add_group
        group.name =
          if catalog_product
            "#{Catalog::Manager.product_catalog_name(catalog_product)} #{catalog_product.sku} — Register Box Saddle"
          elsif dimensions[:shape] == :rectangular
            "Rectangular Side Register Vent"
          else
            "Round Side Register Vent"
          end

        duct_diameter_for_vent =
          if dimensions[:shape] == :round
            dimensions[:diameter]
          else
            nil
          end

        if catalog_product
          plate_width = catalog_product.width.to_f if catalog_product.width.to_f > 0.0
          plate_height = catalog_product.height.to_f if catalog_product.height.to_f > 0.0
        end

        success =
          if catalog_product
            Catalog::MasterFlowGeometry.build_register_box_saddle(
              group: group,
              center: base_center,
              outward_axis: outward_axis,
              duct_axis: axis,
              duct_diameter: duct_diameter_for_vent,
              product: catalog_product
            )
          else
            Geometry::VentBuilder.build_side_register_into(
              group,
              center: base_center,
              outward_axis: outward_axis,
              duct_axis: axis,
              plate_width: plate_width,
              plate_height: plate_height,
              opening_width: plate_width * 0.74,
              opening_height: plate_height * 0.38,
              bumped_out: register_bumped_out,
              duct_diameter: duct_diameter_for_vent
            )
          end

        unless success
          group.erase! if group.valid?
          return nil
        end

        Catalog::Manager.apply_product_metadata(group, catalog_product) if catalog_product

        {
          group: group,
          vent_type: catalog_product ? :catalog_register_box_saddle : :side_register,
          dimensions: dimensions,
          base_center: base_center,
          outward_axis: outward_axis
        }
      rescue => error
        puts "VentInsertService.insert_side_register_at_axis_point failed: #{error.message}"
        puts error.backtrace.join("\n")
        group.erase! if group && group.valid?
        nil
      end

      def self.repeat_step_sign(port_a:, port_b:, repeat_direction:, view: nil)
        direction = repeat_direction.to_s.downcase.to_sym

        if view && view.respond_to?(:screen_coords)
          screen_a = view.screen_coords(port_a.point) rescue nil
          screen_b = view.screen_coords(port_b.point) rescue nil

          if screen_a && screen_b
            dx = screen_b.x.to_f - screen_a.x.to_f

            if dx.abs > 0.001
              axis_goes_right = dx > 0.0

              if direction == :left
                return axis_goes_right ? -1.0 : 1.0
              else
                return axis_goes_right ? 1.0 : -1.0
              end
            end
          end
        end

        direction == :left ? -1.0 : 1.0
      rescue
        repeat_direction.to_s.downcase == "left" ? -1.0 : 1.0
      end

      def self.unique_amounts(amounts)
        clean = []

        Array(amounts).each do |amount|
          next if clean.any? { |existing| (existing - amount).abs <= 0.001 }

          clean << amount
        end

        clean
      rescue
        amounts
      end

      def self.clicked_end_port(network:, ports:, click_point:, dimensions:)
        return nil unless network && network.respond_to?(:open_external_port?)
        return nil unless ports && ports.length >= 2

        port_a = ports[0]
        port_b = ports[1]
        open_ports = ports.select { |port| network.open_external_port?(port) }
        return nil if open_ports.empty?

        largest = Model::DuctDimensions.coerce(dimensions).largest

        threshold = largest * END_CLICK_DISTANCE_FACTOR
        threshold = [threshold, END_CLICK_MAX_DISTANCE].min
        threshold = [threshold, largest * 0.75].max

        best_by_distance = open_ports.min_by { |port| port.point.distance(click_point) }

        if best_by_distance && best_by_distance.point.distance(click_point) <= threshold
          return best_by_distance
        end

        axis = port_a.point.vector_to(port_b.point)
        return nil if axis.length <= EPSILON

        length = axis.length
        axis.normalize!

        projected = port_a.point.vector_to(click_point).dot(axis)

        return port_a if open_ports.include?(port_a) && projected <= threshold
        return port_b if open_ports.include?(port_b) && (length - projected) <= threshold

        nil
      rescue
        nil
      end

      def self.closest_point_on_piece_axis(start_point, end_point, click_point)
        axis = start_point.vector_to(end_point)
        return nil if axis.length <= EPSILON

        length = axis.length
        axis.normalize!

        amount = start_point.vector_to(click_point).dot(axis)
        amount = [[amount, 0.0].max, length].min

        start_point.offset(axis, amount)
      rescue
        nil
      end

      def self.round_outward_axis(axis:, center_point:, click_point:)
        axis = Geometry::RectangularFrame.normalized(axis)
        return nil unless axis

        raw = center_point.vector_to(click_point)
        raw = Geometry::RectangularFrame.perpendicularized(raw, axis)

        top_axis = Geometry::RectangularFrame.perpendicularized(
          Geom::Vector3d.new(0, 0, 1),
          axis
        )

        top_axis ||= fallback_perpendicular_axis(axis)
        return nil unless top_axis

        top_axis.normalize!

        side_axis = axis.cross(top_axis)
        return nil if side_axis.length <= EPSILON
        side_axis.normalize!

        if raw && raw.length > EPSILON
          raw.normalize!
          quantized_outward_axis(raw, top_axis, side_axis)
        else
          top_axis
        end
      rescue
        nil
      end

      def self.rectangular_outward_axis(port:, axis:, center_point:, click_point:)
        basis = Geometry::RectangularFrame.stable_basis_for_axis(
          axis,
          port.width,
          port.height,
          preferred_width_axis: port.width_axis,
          preferred_height_axis: port.height_axis,
          allow_relevel: false
        )

        return nil unless basis

        raw = center_point.vector_to(click_point)
        raw = Geometry::RectangularFrame.perpendicularized(raw, axis)

        width_axis = basis[:width_axis]
        height_axis = basis[:height_axis]

        return height_axis unless raw && raw.length > EPSILON

        raw.normalize!
        quantized_outward_axis(raw, height_axis, width_axis)
      rescue
        nil
      end

      def self.quantized_outward_axis(raw_axis, primary_axis, secondary_axis)
        raw_axis = Geometry::RectangularFrame.normalized(raw_axis)
        primary_axis = Geometry::RectangularFrame.normalized(primary_axis)
        secondary_axis = Geometry::RectangularFrame.normalized(secondary_axis)

        return nil unless raw_axis && primary_axis && secondary_axis

        candidates = []

        candidates << primary_axis
        candidates << normalized_sum(primary_axis, secondary_axis)
        candidates << secondary_axis
        candidates << normalized_sum(primary_axis.clone.reverse, secondary_axis)
        candidates << primary_axis.clone.reverse
        candidates << normalized_sum(primary_axis.clone.reverse, secondary_axis.clone.reverse)
        candidates << secondary_axis.clone.reverse
        candidates << normalized_sum(primary_axis, secondary_axis.clone.reverse)

        best = candidates.compact.max_by { |candidate| candidate.dot(raw_axis) }
        best ||= primary_axis

        best.normalize!
        best
      rescue
        nil
      end

      def self.normalized_sum(vector_a, vector_b)
        return nil unless vector_a && vector_b

        result = Geom::Vector3d.new(
          vector_a.x + vector_b.x,
          vector_a.y + vector_b.y,
          vector_a.z + vector_b.z
        )

        return nil if result.length <= EPSILON

        result.normalize!
        result
      rescue
        nil
      end

      def self.rectangular_surface_center(port:, axis:, center_point:, outward_axis:, dimensions:)
        basis = Geometry::RectangularFrame.stable_basis_for_axis(
          axis,
          dimensions[:width],
          dimensions[:height],
          preferred_width_axis: port.width_axis,
          preferred_height_axis: port.height_axis,
          allow_relevel: false
        )

        return center_point unless basis

        width_axis = basis[:width_axis]
        height_axis = basis[:height_axis]

        width_dot = outward_axis.dot(width_axis)
        height_dot = outward_axis.dot(height_axis)

        width_component =
          if width_dot.abs >= 0.35
            width_axis.clone.tap { |v| v.reverse! if width_dot < 0.0 }
          else
            nil
          end

        height_component =
          if height_dot.abs >= 0.35
            height_axis.clone.tap { |v| v.reverse! if height_dot < 0.0 }
          else
            nil
          end

        result = center_point.clone

        if width_component
          result = result.offset(width_component, dimensions[:width].to_f / 2.0)
        end

        if height_component
          result = result.offset(height_component, dimensions[:height].to_f / 2.0)
        end

        unless width_component || height_component
          width_abs = width_dot.abs
          height_abs = height_dot.abs

          if width_abs >= height_abs
            direction = width_axis.clone
            direction.reverse! if width_dot < 0.0
            result = center_point.offset(direction, dimensions[:width].to_f / 2.0)
          else
            direction = height_axis.clone
            direction.reverse! if height_dot < 0.0
            result = center_point.offset(direction, dimensions[:height].to_f / 2.0)
          end
        end

        result
      rescue
        center_point
      end

      def self.fallback_perpendicular_axis(axis)
        axis = Geometry::RectangularFrame.normalized(axis)
        return nil unless axis

        candidates = [
          Geom::Vector3d.new(0, 0, 1),
          Geom::Vector3d.new(1, 0, 0),
          Geom::Vector3d.new(0, 1, 0)
        ]

        candidates.each do |candidate|
          result = Geometry::RectangularFrame.perpendicularized(candidate, axis)
          return result if result
        end

        nil
      rescue
        nil
      end
    end
  end
end
