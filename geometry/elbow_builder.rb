module DuctExtension
  module Geometry
    module ElbowBuilder
      SEGMENTS = 32
      CIRCLE_SEGMENTS = 32
      EPSILON = 0.000001

      # Small visual overlap collars at the tangent ends of elbows. These do not
      # move the graph ports. They just let elbows tuck slightly into adjacent
      # straight duct, which hides the sharp cut/blue-cap artifacts that show up
      # on tight bends.
      END_COLLAR_FACTOR = 0.18
      MAX_END_COLLAR_TO_RADIUS = 0.18
      MIN_VISIBLE_COLLAR = 0.05

      def self.build_into(
        group,
        start_point,
        entry_vector,
        exit_vector,
        diameter,
        bend_radius,
        cap_start: false,
        cap_end: false
      )
        return false unless group && group.valid?

        start_point = RectangularFrame.point3d(start_point)
        entry_vector = RectangularFrame.normalized(entry_vector)
        exit_vector = RectangularFrame.normalized(exit_vector)

        diameter = diameter.to_f
        bend_radius = bend_radius.to_f

        return false unless start_point && entry_vector && exit_vector
        return false if diameter <= 0.0 || bend_radius <= 0.0

        arc = arc_data(
          start_point: start_point,
          entry_vector: entry_vector,
          exit_vector: exit_vector,
          bend_radius: bend_radius
        )

        return false unless arc

        radius = diameter / 2.0

        # Critical improvement:
        # Build one stable circular frame at the start, then rotate that same
        # frame through the elbow. Do NOT recalculate the circle basis at every
        # ring, because that can flip/twist and create pinched seams.
        start_axis_a, start_axis_b = stable_circle_basis(
          entry_vector,
          arc[:normal]
        )

        return false unless start_axis_a && start_axis_b

        rings = []
        ring_centers = []

        (SEGMENTS + 1).times do |index|
          t = index.to_f / SEGMENTS.to_f
          theta = arc[:angle] * t

          rotation = Geom::Transformation.rotation(
            arc[:center],
            arc[:normal],
            theta
          )

          ring_center = start_point.transform(rotation)
          axis_a = start_axis_a.transform(rotation)
          axis_b = start_axis_b.transform(rotation)

          axis_a.normalize!
          axis_b.normalize!

          ring_centers << ring_center
          rings << ring_points(
            ring_center,
            axis_a,
            axis_b,
            radius,
            CIRCLE_SEGMENTS
          )
        end

        entities = group.entities

        SEGMENTS.times do |ring_index|
          current_ring = rings[ring_index]
          next_ring = rings[ring_index + 1]

          CIRCLE_SEGMENTS.times do |point_index|
            next_point_index = (point_index + 1) % CIRCLE_SEGMENTS

            Mesh.add_quad(
              entities,
              current_ring[point_index],
              current_ring[next_point_index],
              next_ring[next_point_index],
              next_ring[point_index]
            )
          end
        end

        end_point = ring_centers.last

        add_tangent_overlap_collars(
          group: group,
          start_point: start_point,
          end_point: end_point,
          entry_vector: entry_vector,
          exit_vector: exit_vector,
          diameter: diameter,
          bend_radius: bend_radius,
          angle: arc[:angle]
        )

        if cap_start
          Mesh.add_face_safe(
            entities,
            rings.first.reverse,
            reverse_if_normal_against: entry_vector.clone.reverse
          )
        end

        if cap_end
          Mesh.add_face_safe(
            entities,
            rings.last,
            reverse_if_normal_against: exit_vector
          )
        end

        soften_elbow_edges(group)
        add_clean_end_rings(
          group: group,
          start_point: start_point,
          end_point: end_point,
          entry_vector: entry_vector,
          exit_vector: exit_vector,
          diameter: diameter
        )

        Mesh.apply_material_from_group(group)

        true
      rescue => error
        puts "ElbowBuilder.build_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.exit_point(start_point, entry_vector, exit_vector, bend_radius)
        start_point = RectangularFrame.point3d(start_point)
        entry_vector = RectangularFrame.normalized(entry_vector)
        exit_vector = RectangularFrame.normalized(exit_vector)
        bend_radius = bend_radius.to_f

        return nil unless start_point && entry_vector && exit_vector
        return nil if bend_radius <= 0.0

        arc = arc_data(
          start_point: start_point,
          entry_vector: entry_vector,
          exit_vector: exit_vector,
          bend_radius: bend_radius
        )

        return nil unless arc

        rotation = Geom::Transformation.rotation(
          arc[:center],
          arc[:normal],
          arc[:angle]
        )

        # Important: this remains the true graph port location. The visual
        # collars overlap past this point, but they do not change routing math.
        start_point.transform(rotation)
      rescue => error
        puts "ElbowBuilder.exit_point failed: #{error.message}"
        nil
      end

      def self.arc_data(start_point:, entry_vector:, exit_vector:, bend_radius:)
        entry = RectangularFrame.normalized(entry_vector)
        exitv = RectangularFrame.normalized(exit_vector)

        return nil unless entry && exitv

        angle = entry.angle_between(exitv)
        return nil if angle <= EPSILON
        return nil if angle >= Math::PI - EPSILON

        normal = entry.cross(exitv)
        return nil if normal.length <= EPSILON
        normal.normalize!

        center_offset = normal.cross(entry)
        return nil if center_offset.length <= EPSILON
        center_offset.normalize!

        center = start_point.offset(center_offset, bend_radius)

        {
          center: center,
          normal: normal,
          angle: angle
        }
      end

      def self.stable_circle_basis(tangent, bend_normal)
        tangent = RectangularFrame.normalized(tangent)
        bend_normal = RectangularFrame.normalized(bend_normal)

        return nil unless tangent && bend_normal

        # The bend normal is perpendicular to the tangent, so it is a very stable
        # first ring axis. The second ring axis completes the circular frame.
        axis_a = bend_normal.clone
        axis_b = tangent.cross(axis_a)

        return nil if axis_b.length <= EPSILON

        axis_a.normalize!
        axis_b.normalize!

        [axis_a, axis_b]
      end

      def self.ring_points(center, axis_a, axis_b, radius, segments)
        points = []

        segments.times do |index|
          angle = (Math::PI * 2.0 * index) / segments.to_f

          radial = Geom::Vector3d.new(
            axis_a.x * Math.cos(angle) + axis_b.x * Math.sin(angle),
            axis_a.y * Math.cos(angle) + axis_b.y * Math.sin(angle),
            axis_a.z * Math.cos(angle) + axis_b.z * Math.sin(angle)
          )

          radial.normalize!

          points << center.offset(radial, radius)
        end

        points
      end

      def self.circle_basis(direction)
        direction = RectangularFrame.normalized(direction)
        return nil unless direction

        reference = RectangularFrame.best_reference_axis(direction)

        axis_a = direction.cross(reference)
        return nil if axis_a.length <= EPSILON

        axis_a.normalize!

        axis_b = direction.cross(axis_a)
        return nil if axis_b.length <= EPSILON

        axis_b.normalize!

        [axis_a, axis_b]
      end

      def self.add_tangent_overlap_collars(
        group:,
        start_point:,
        end_point:,
        entry_vector:,
        exit_vector:,
        diameter:,
        bend_radius:,
        angle:
      )
        collar = elbow_collar_length(
          diameter: diameter,
          bend_radius: bend_radius,
          angle: angle
        )

        return if collar <= MIN_VISIBLE_COLLAR

        start_collar_start = start_point.offset(entry_vector.clone.reverse, collar)
        end_collar_end = end_point.offset(exit_vector, collar)

        PipeBuilder.build_into(
          group,
          start_collar_start,
          start_point,
          diameter,
          overlap_start: false,
          overlap_end: false,
          cap_start: false,
          cap_end: false
        )

        PipeBuilder.build_into(
          group,
          end_point,
          end_collar_end,
          diameter,
          overlap_start: false,
          overlap_end: false,
          cap_start: false,
          cap_end: false
        )
      rescue => error
        puts "ElbowBuilder.add_tangent_overlap_collars failed: #{error.message}"
      end

      def self.elbow_collar_length(diameter:, bend_radius:, angle:)
        diameter = diameter.to_f
        bend_radius = bend_radius.to_f
        angle = angle.to_f

        base = diameter * END_COLLAR_FACTOR
        radius_cap = bend_radius * MAX_END_COLLAR_TO_RADIUS

        # Tighter and more U-shaped elbows get a little more visual overlap.
        tightness_boost = [[angle / (Math::PI / 2.0), 1.5].min, 0.75].max

        [base * tightness_boost, radius_cap].min
      rescue
        0.0
      end

      def self.add_clean_end_rings(group:, start_point:, end_point:, entry_vector:, exit_vector:, diameter:)
        radius = diameter.to_f / 2.0

        add_round_socket_ring(
          group: group,
          center: start_point,
          direction: entry_vector,
          radius: radius,
          segments: CIRCLE_SEGMENTS
        )

        add_round_socket_ring(
          group: group,
          center: end_point,
          direction: exit_vector,
          radius: radius,
          segments: CIRCLE_SEGMENTS
        )
      rescue => error
        puts "ElbowBuilder.add_clean_end_rings failed: #{error.message}"
      end

      def self.add_round_socket_ring(group:, center:, direction:, radius:, segments:)
        axis_a, axis_b = circle_basis(direction)
        return unless axis_a && axis_b

        points = ring_points(center, axis_a, axis_b, radius, segments)
        entities = group.entities

        segments.times do |index|
          next_index = (index + 1) % segments

          edge = entities.add_line(points[index], points[next_index])
          next unless edge

          edge.hidden = false
          edge.soft = false if edge.respond_to?(:soft=)
          edge.smooth = false if edge.respond_to?(:smooth=)
        end
      rescue => error
        puts "ElbowBuilder.add_round_socket_ring failed: #{error.message}"
      end

      def self.soften_elbow_edges(group)
        return unless group && group.valid?

        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          edge.soft = true
          edge.smooth = true
          edge.hidden = false
        end
      rescue => error
        puts "ElbowBuilder.soften_elbow_edges failed: #{error.message}"
      end

      private_class_method :arc_data
      private_class_method :stable_circle_basis
      private_class_method :ring_points
      private_class_method :add_tangent_overlap_collars
      private_class_method :elbow_collar_length
      private_class_method :add_clean_end_rings
      private_class_method :add_round_socket_ring
      private_class_method :soften_elbow_edges
    end
  end
end
