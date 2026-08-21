module DuctExtension
  module Geometry
    module ElbowBuilder
      SEGMENTS = 32
      CIRCLE_SEGMENTS = 32
      EPSILON = 0.000001

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

        # Round connections use one deterministic facet frame everywhere.
        # A former visual-overlap collar used PipeBuilder's frame while the
        # curved elbow body used a bend-normal frame. Those equal-diameter
        # 32-gons were rotated relative to one another, producing a real
        # crescent-shaped mismatch at pipe/elbow joins.
        #
        # Start in the exact PipeBuilder frame, rigidly transport it around the
        # bend, then distribute the harmless circular-section phase correction
        # needed to land on PipeBuilder's exact exit frame as well. The circle
        # is rotationally symmetric, so this changes only polygon tessellation,
        # never the physical bend, port point, radius, or routing math.
        start_axis_a, start_axis_b = circle_basis(entry_vector)
        desired_exit_axis_a, = circle_basis(exit_vector)
        return false unless start_axis_a && start_axis_b && desired_exit_axis_a

        end_rotation = Geom::Transformation.rotation(
          arc[:center],
          arc[:normal],
          arc[:angle]
        )
        raw_exit_axis_a = start_axis_a.transform(end_rotation)
        raw_exit_axis_a.normalize!
        phase_error = signed_angle_about_axis(
          raw_exit_axis_a,
          desired_exit_axis_a,
          exit_vector
        )

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
          tangent = entry_vector.transform(rotation)
          tangent.normalize!
          axis_a = start_axis_a.transform(rotation)
          axis_b = start_axis_b.transform(rotation)

          if phase_error.abs > EPSILON
            phase_rotation = Geom::Transformation.rotation(
              Geom::Point3d.new(0, 0, 0),
              tangent,
              phase_error * t
            )
            axis_a = axis_a.transform(phase_rotation)
            axis_b = axis_b.transform(phase_rotation)
          end

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
        hide_connection_rings(group.entities, rings.first, rings.last)

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

      def self.signed_angle_about_axis(from_vector, to_vector, axis)
        from = RectangularFrame.normalized(from_vector)
        to = RectangularFrame.normalized(to_vector)
        normal = RectangularFrame.normalized(axis)
        return 0.0 unless from && to && normal

        angle = from.angle_between(to)
        cross = from.cross(to)
        normal.dot(cross) < 0.0 ? -angle : angle
      rescue
        0.0
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
        # PipeBuilder is the single authority for round connector facet phase.
        # Elbows must use the same frame or equal-diameter 32-gons can meet at
        # different rotations and leave visible crescent gaps.
        PipeBuilder.circle_basis(direction)
      rescue
        nil
      end

      def self.hide_connection_rings(entities, *rings)
        edges = entities.grep(Sketchup::Edge)

        Array(rings).compact.each do |ring|
          ring.length.times do |index|
            next_index = (index + 1) % ring.length
            point_a = ring[index]
            point_b = ring[next_index]

            edge = edges.find do |candidate|
              edge_matches_segment?(candidate, point_a, point_b)
            end
            next unless edge && edge.valid?

            edge.hidden = true
            edge.soft = true if edge.respond_to?(:soft=)
            edge.smooth = true if edge.respond_to?(:smooth=)
          end
        end
      rescue => error
        puts "ElbowBuilder.hide_connection_rings failed: #{error.message}"
      end

      def self.edge_matches_segment?(edge, point_a, point_b)
        return false unless edge && edge.valid?

        a = edge.start.position
        b = edge.end.position
        same_forward = a.distance(point_a) <= EPSILON && b.distance(point_b) <= EPSILON
        same_reverse = a.distance(point_b) <= EPSILON && b.distance(point_a) <= EPSILON
        same_forward || same_reverse
      rescue
        false
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
      private_class_method :signed_angle_about_axis
      private_class_method :ring_points
      private_class_method :hide_connection_rings
      private_class_method :edge_matches_segment?
      private_class_method :soften_elbow_edges
    end
  end
end

