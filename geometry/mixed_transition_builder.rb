module DuctExtension
  module Geometry
    # Builds rectangular<->round sheet-metal transitions. ReducerBuilder owns
    # transition selection/length policy; this module owns only mixed geometry.
    module MixedTransitionBuilder
      SEGMENTS = 32
      EPSILON = 0.000001

      def self.build_into(
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
        return false unless group && group.valid? && start_point && end_point

        direction = start_point.vector_to(end_point)
        total_length = direction.length
        return false if total_length <= EPSILON
        direction.normalize!

        basis = RectangularFrame.basis_for_axis(
          direction,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis
        )
        return false unless basis

        largest = [
          start_dimensions[:diameter], start_dimensions[:width], start_dimensions[:height],
          end_dimensions[:diameter], end_dimensions[:width], end_dimensions[:height]
        ].compact.map(&:to_f).max

        collar_length = [[total_length * 0.16, largest * 0.22].min, 0.0].max
        taper_start = start_point.offset(direction, collar_length)
        taper_end = end_point.offset(direction.clone.reverse, collar_length)

        profiles = [
          profile(start_point, start_dimensions, basis),
          profile(taper_start, start_dimensions, basis),
          profile(taper_end, end_dimensions, basis),
          profile(end_point, end_dimensions, basis)
        ]
        return false unless profiles.all? { |ring| ring.length == SEGMENTS }

        entities = group.entities
        add_strip(entities, profiles[0], profiles[1])
        add_strip(entities, profiles[1], profiles[2])
        add_strip(entities, profiles[2], profiles[3])
        hide_mesh_edges(entities)

        if start_dimensions[:shape] == :rectangular
          add_rectangular_details(
            entities: entities,
            outer_center: start_point,
            collar_center: taper_start,
            dimensions: start_dimensions,
            basis: basis,
            rectangular_profile: profiles[1],
            round_profile: profiles[2]
          )
          add_ring_edges(entities, profiles[2])
          add_ring_edges(entities, profiles[3])
        else
          add_ring_edges(entities, profiles[0])
          add_ring_edges(entities, profiles[1])
          add_rectangular_details(
            entities: entities,
            outer_center: end_point,
            collar_center: taper_end,
            dimensions: end_dimensions,
            basis: basis,
            rectangular_profile: profiles[2],
            round_profile: profiles[1]
          )
        end

        Mesh.apply_material_from_group(group)
        true
      rescue => error
        puts "MixedTransitionBuilder.build_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.profile(center, dimensions, basis)
        if dimensions[:shape] == :rectangular
          rectangle_profile(
            center: center,
            width_axis: basis[:width_axis],
            height_axis: basis[:height_axis],
            width: dimensions[:width],
            height: dimensions[:height]
          )
        else
          round_profile(
            center: center,
            width_axis: basis[:width_axis],
            height_axis: basis[:height_axis],
            radius: dimensions[:diameter].to_f / 2.0
          )
        end
      end
      private_class_method :profile

      # 8 samples per side. Corners are indices 0/8/16/24, which lets the
      # four visible sheet-metal seams land on stable corner locations.
      def self.rectangle_profile(center:, width_axis:, height_axis:, width:, height:)
        half_width = width.to_f / 2.0
        half_height = height.to_f / 2.0
        corners = [
          [ half_width,  half_height], [-half_width,  half_height],
          [-half_width, -half_height], [ half_width, -half_height]
        ]

        4.times.flat_map do |side|
          a = corners[side]
          b = corners[(side + 1) % 4]
          (SEGMENTS / 4).times.map do |index|
            t = index.to_f / (SEGMENTS / 4).to_f
            point_from_offsets(
              center, width_axis, height_axis,
              a[0] + (b[0] - a[0]) * t,
              a[1] + (b[1] - a[1]) * t
            )
          end
        end
      end
      private_class_method :rectangle_profile

      def self.round_profile(center:, width_axis:, height_axis:, radius:)
        phase = Math::PI / 4.0
        SEGMENTS.times.map do |index|
          angle = phase + Math::PI * 2.0 * index / SEGMENTS.to_f
          point_from_offsets(
            center, width_axis, height_axis,
            Math.cos(angle) * radius.to_f,
            Math.sin(angle) * radius.to_f
          )
        end
      end
      private_class_method :round_profile

      def self.point_from_offsets(center, width_axis, height_axis, width_offset, height_offset)
        Geom::Point3d.new(
          center.x + width_axis.x * width_offset + height_axis.x * height_offset,
          center.y + width_axis.y * width_offset + height_axis.y * height_offset,
          center.z + width_axis.z * width_offset + height_axis.z * height_offset
        )
      end
      private_class_method :point_from_offsets

      def self.add_strip(entities, a, b)
        SEGMENTS.times do |index|
          next_index = (index + 1) % SEGMENTS
          Mesh.add_quad(entities, a[index], a[next_index], b[next_index], b[index])
        end
      end
      private_class_method :add_strip

      def self.hide_mesh_edges(entities)
        entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?
          edge.hidden = true
          edge.soft = true if edge.respond_to?(:soft=)
          edge.smooth = true if edge.respond_to?(:smooth=)
        end
      end
      private_class_method :hide_mesh_edges

      def self.add_rectangular_details(
        entities:,
        outer_center:,
        collar_center:,
        dimensions:,
        basis:,
        rectangular_profile:,
        round_profile:
      )
        outer = RectangularFrame.rectangle_corners_from_basis(
          outer_center, basis[:width_axis], basis[:height_axis],
          dimensions[:width], dimensions[:height]
        )
        collar = RectangularFrame.rectangle_corners_from_basis(
          collar_center, basis[:width_axis], basis[:height_axis],
          dimensions[:width], dimensions[:height]
        )

        [outer, collar].each do |corners|
          4.times { |i| visible_edge(entities, corners[i], corners[(i + 1) % 4]) }
        end

        indices = [0, SEGMENTS / 4, SEGMENTS / 2, SEGMENTS * 3 / 4]
        4.times do |i|
          visible_edge(entities, outer[i], collar[i])
          visible_edge(entities, rectangular_profile[indices[i]], round_profile[indices[i]])
        end
      rescue => error
        puts "MixedTransitionBuilder.add_rectangular_details failed: #{error.message}"
      end
      private_class_method :add_rectangular_details

      def self.add_ring_edges(entities, ring)
        SEGMENTS.times do |index|
          visible_edge(entities, ring[index], ring[(index + 1) % SEGMENTS])
        end
      end
      private_class_method :add_ring_edges

      def self.visible_edge(entities, a, b)
        PrimitiveHelpers.add_visible_edge(entities, a, b, min_distance: EPSILON)
      end
      private_class_method :visible_edge
    end
  end
end
