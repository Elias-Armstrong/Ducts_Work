module DuctExtension
  module Geometry
    module ReducerBuilder
      ROUND_SEGMENTS = 32
      EPSILON = 0.000001

      COLLAR_LENGTH_FACTOR = 0.42
      MAX_COLLAR_TOTAL_FRACTION = 0.42
      MIN_TAPER_LENGTH_FACTOR = 0.85

      def self.build_into(
        group,
        start_point,
        end_point,
        start_dimensions:,
        end_dimensions:,
        preferred_width_axis: nil,
        preferred_height_axis: nil
      )
        return false unless group && group.valid?

        start_dimensions = normalize_dimensions(start_dimensions)
        end_dimensions = normalize_dimensions(end_dimensions)

        return false unless start_dimensions && end_dimensions

        if start_dimensions[:shape] != end_dimensions[:shape]
          return MixedTransitionBuilder.build_into(
            group,
            start_point,
            end_point,
            start_dimensions: start_dimensions,
            end_dimensions: end_dimensions,
            preferred_width_axis: preferred_width_axis,
            preferred_height_axis: preferred_height_axis
          )
        end

        if start_dimensions[:shape] == :rectangular
          build_rectangular(
            group,
            start_point,
            end_point,
            start_dimensions: start_dimensions,
            end_dimensions: end_dimensions,
            preferred_width_axis: preferred_width_axis,
            preferred_height_axis: preferred_height_axis
          )
        else
          build_round(
            group,
            start_point,
            end_point,
            start_dimensions: start_dimensions,
            end_dimensions: end_dimensions
          )
        end
      rescue => error
        puts "ReducerBuilder.build_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.default_length(start_dimensions, end_dimensions)
        start_dimensions = normalize_dimensions(start_dimensions)
        end_dimensions = normalize_dimensions(end_dimensions)

        return 12.0 unless start_dimensions && end_dimensions

        largest = [
          start_dimensions[:diameter],
          start_dimensions[:width],
          start_dimensions[:height],
          end_dimensions[:diameter],
          end_dimensions[:width],
          end_dimensions[:height]
        ].compact.map(&:to_f).max

        if start_dimensions[:shape] != end_dimensions[:shape]
          # Mixed rectangular/round takeoffs should look like a compact
          # sheet-metal transition, not a long inline reducer.
          return [largest * 0.75, 4.0].max
        end

        delta =
          if start_dimensions[:shape] == :rectangular
            [
              (end_dimensions[:width].to_f - start_dimensions[:width].to_f).abs,
              (end_dimensions[:height].to_f - start_dimensions[:height].to_f).abs
            ].max
          else
            (end_dimensions[:diameter].to_f - start_dimensions[:diameter].to_f).abs
          end

        # Includes two short straight collars plus the tapered body.
        [largest * 2.1, delta * 3.0, 10.0].max
      rescue
        12.0
      end

      def self.build_round(group, start_point, end_point, start_dimensions:, end_dimensions:)
        start_point = PipeBuilder.to_point(start_point)
        end_point = PipeBuilder.to_point(end_point)

        return false unless start_point && end_point

        direction = start_point.vector_to(end_point)
        total_length = direction.length
        return false if total_length <= EPSILON

        direction.normalize!

        start_diameter = start_dimensions[:diameter].to_f
        end_diameter = end_dimensions[:diameter].to_f

        return false if start_diameter <= 0.0 || end_diameter <= 0.0

        start_radius = start_diameter / 2.0
        end_radius = end_diameter / 2.0

        collar_length = reducer_collar_length(
          total_length: total_length,
          start_size: start_diameter,
          end_size: end_diameter
        )

        taper_start = start_point.offset(direction, collar_length)
        taper_end = end_point.offset(direction.clone.reverse, collar_length)

        axis_a, axis_b = PipeBuilder.circle_basis(direction)
        return false unless axis_a && axis_b

        start_ring = PipeBuilder.ring_points(start_point, axis_a, axis_b, start_radius, ROUND_SEGMENTS)
        taper_start_ring = PipeBuilder.ring_points(taper_start, axis_a, axis_b, start_radius, ROUND_SEGMENTS)
        taper_end_ring = PipeBuilder.ring_points(taper_end, axis_a, axis_b, end_radius, ROUND_SEGMENTS)
        end_ring = PipeBuilder.ring_points(end_point, axis_a, axis_b, end_radius, ROUND_SEGMENTS)

        entities = group.entities

        add_round_ring_strip(entities, start_ring, taper_start_ring)
        add_round_ring_strip(entities, taper_start_ring, taper_end_ring)
        add_round_ring_strip(entities, taper_end_ring, end_ring)

        Mesh.soft_smooth_round_edges(group)

        # Do this after smoothing so only the true socket and transition rings are hard/visible.
        add_round_ring_edges(entities, start_ring)
        add_round_ring_edges(entities, taper_start_ring)
        add_round_ring_edges(entities, taper_end_ring)
        add_round_ring_edges(entities, end_ring)

        Mesh.apply_material_from_group(group)

        true
      rescue => error
        puts "ReducerBuilder.build_round failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.build_rectangular(
        group,
        start_point,
        end_point,
        start_dimensions:,
        end_dimensions:,
        preferred_width_axis: nil,
        preferred_height_axis: nil
      )
        start_point = RectangularFrame.point3d(start_point)
        end_point = RectangularFrame.point3d(end_point)

        return false unless start_point && end_point

        direction = start_point.vector_to(end_point)
        total_length = direction.length
        return false if total_length <= EPSILON

        direction.normalize!

        start_width = start_dimensions[:width].to_f
        start_height = start_dimensions[:height].to_f
        end_width = end_dimensions[:width].to_f
        end_height = end_dimensions[:height].to_f

        return false if start_width <= 0.0 || start_height <= 0.0
        return false if end_width <= 0.0 || end_height <= 0.0

        basis = RectangularFrame.basis_for_axis(
          direction,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis
        )

        return false unless basis

        collar_length = reducer_collar_length(
          total_length: total_length,
          start_size: [start_width, start_height].max,
          end_size: [end_width, end_height].max
        )

        taper_start = start_point.offset(direction, collar_length)
        taper_end = end_point.offset(direction.clone.reverse, collar_length)

        start_corners = RectangularFrame.rectangle_corners_from_basis(
          start_point,
          basis[:width_axis],
          basis[:height_axis],
          start_width,
          start_height
        )

        taper_start_corners = RectangularFrame.rectangle_corners_from_basis(
          taper_start,
          basis[:width_axis],
          basis[:height_axis],
          start_width,
          start_height
        )

        taper_end_corners = RectangularFrame.rectangle_corners_from_basis(
          taper_end,
          basis[:width_axis],
          basis[:height_axis],
          end_width,
          end_height
        )

        end_corners = RectangularFrame.rectangle_corners_from_basis(
          end_point,
          basis[:width_axis],
          basis[:height_axis],
          end_width,
          end_height
        )

        return false if start_corners.empty? || taper_start_corners.empty?
        return false if taper_end_corners.empty? || end_corners.empty?

        entities = group.entities

        add_rectangular_section_strip(entities, start_corners, taper_start_corners)
        add_rectangular_section_strip(entities, taper_start_corners, taper_end_corners)
        add_rectangular_section_strip(entities, taper_end_corners, end_corners)

        add_rectangular_outline_edges(
          entities,
          start_corners,
          taper_start_corners,
          taper_end_corners,
          end_corners
        )

        Mesh.keep_edges_visible(group)
        Mesh.apply_material_from_group(group)

        true
      rescue => error
        puts "ReducerBuilder.build_rectangular failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end


      def self.reducer_collar_length(total_length:, start_size:, end_size:)
        total_length = total_length.to_f
        largest = [start_size.to_f, end_size.to_f].max
        delta = (end_size.to_f - start_size.to_f).abs

        desired = largest * COLLAR_LENGTH_FACTOR
        min_taper = [delta * MIN_TAPER_LENGTH_FACTOR, largest * 0.55, 2.0].max
        max_each = [((total_length - min_taper) / 2.0), total_length * (MAX_COLLAR_TOTAL_FRACTION / 2.0)].min

        [[desired, max_each].min, 0.0].max
      rescue
        0.0
      end

      def self.add_round_ring_strip(entities, ring_a, ring_b)
        count = [ring_a.length, ring_b.length].min

        count.times do |index|
          next_index = (index + 1) % count

          Mesh.add_quad(
            entities,
            ring_a[index],
            ring_a[next_index],
            ring_b[next_index],
            ring_b[index]
          )
        end
      rescue => error
        puts "ReducerBuilder.add_round_ring_strip failed: #{error.message}"
      end

      def self.add_round_ring_edges(entities, ring)
        count = ring.length

        count.times do |index|
          next_index = (index + 1) % count
          edge = entities.add_line(ring[index], ring[next_index])
          next unless edge

          edge.hidden = false
          edge.soft = false if edge.respond_to?(:soft=)
          edge.smooth = false if edge.respond_to?(:smooth=)
        end
      rescue => error
        puts "ReducerBuilder.add_round_ring_edges failed: #{error.message}"
      end

      def self.add_rectangular_section_strip(entities, section_a, section_b)
        4.times do |index|
          next_index = (index + 1) % 4

          Mesh.add_quad(
            entities,
            section_a[index],
            section_a[next_index],
            section_b[next_index],
            section_b[index]
          )
        end
      rescue => error
        puts "ReducerBuilder.add_rectangular_section_strip failed: #{error.message}"
      end

      def self.add_rectangular_outline_edges(entities, start_corners, taper_start_corners, taper_end_corners, end_corners)
        [start_corners, taper_start_corners, taper_end_corners, end_corners].each do |corners|
          4.times do |index|
            next_index = (index + 1) % 4
            add_visible_edge(entities, corners[index], corners[next_index])
          end
        end

        4.times do |index|
          add_visible_edge(entities, start_corners[index], taper_start_corners[index])
          add_visible_edge(entities, taper_start_corners[index], taper_end_corners[index])
          add_visible_edge(entities, taper_end_corners[index], end_corners[index])
        end
      rescue => error
        puts "ReducerBuilder.add_rectangular_outline_edges failed: #{error.message}"
      end

      def self.add_visible_edge(entities, point_a, point_b)
        PrimitiveHelpers.add_visible_edge(
          entities,
          point_a,
          point_b,
          min_distance: EPSILON
        )
      end

      def self.normalize_dimensions(dimensions)
        return nil unless dimensions

        shape = Model::DuctDimensions.normalize_shape(dimensions[:shape] || dimensions["shape"])

        if shape == :rectangular
          width = positive(dimensions[:width] || dimensions["width"])
          height = positive(dimensions[:height] || dimensions["height"])

          return nil unless width && height

          {
            shape: :rectangular,
            diameter: [width, height].max,
            width: width,
            height: height
          }
        else
          diameter = positive(dimensions[:diameter] || dimensions["diameter"])

          return nil unless diameter

          {
            shape: :round,
            diameter: diameter,
            width: diameter,
            height: diameter
          }
        end
      end

      def self.positive(value)
        number = value.to_f
        number > 0.0 ? number : nil
      rescue
        nil
      end

      private_class_method :build_round
      private_class_method :build_rectangular
      private_class_method :reducer_collar_length
      private_class_method :add_round_ring_strip
      private_class_method :add_round_ring_edges
      private_class_method :add_rectangular_section_strip
      private_class_method :add_rectangular_outline_edges
      private_class_method :add_visible_edge
      private_class_method :normalize_dimensions
      private_class_method :positive
    end
  end
end
