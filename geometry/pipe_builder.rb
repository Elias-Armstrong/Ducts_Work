module DuctExtension
  module Geometry
    module PipeBuilder
      SEGMENTS = 32
      OVERLAP_FACTOR = 0.10
      EPSILON = 0.000001

      def self.build_into(
        group,
        start_point,
        end_point,
        diameter,
        overlap_start: false,
        overlap_end: false,
        cap_start: true,
        cap_end: true
      )
        return false unless group && group.valid?

        start_point = to_point(start_point)
        end_point = to_point(end_point)
        diameter = diameter.to_f

        return false unless start_point && end_point
        return false if diameter <= 0.0

        direction = start_point.vector_to(end_point)
        return false if direction.length <= EPSILON

        direction.normalize!

        radius = diameter / 2.0
        overlap = diameter * OVERLAP_FACTOR

        mesh_start = overlap_start ? start_point.offset(direction.clone.reverse, overlap) : start_point
        mesh_end = overlap_end ? end_point.offset(direction, overlap) : end_point

        axis_a, axis_b = circle_basis(direction)
        return false unless axis_a && axis_b

        start_ring = ring_points(mesh_start, axis_a, axis_b, radius, SEGMENTS)
        end_ring = ring_points(mesh_end, axis_a, axis_b, radius, SEGMENTS)

        entities = group.entities

        SEGMENTS.times do |index|
          next_index = (index + 1) % SEGMENTS

          Mesh.add_quad(
            entities,
            start_ring[index],
            start_ring[next_index],
            end_ring[next_index],
            end_ring[index]
          )
        end

        if cap_start
          face = Mesh.add_face_safe(
            entities,
            start_ring.reverse,
            reverse_if_normal_against: direction.clone.reverse
          )

          face.material = group.material if face && group.material
        end

        if cap_end
          face = Mesh.add_face_safe(
            entities,
            end_ring,
            reverse_if_normal_against: direction
          )

          face.material = group.material if face && group.material
        end

        Mesh.soft_smooth_round_edges(group)
        Mesh.apply_material_from_group(group)

        true
      rescue => error
        puts "PipeBuilder.build_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.ring_points(center, axis_a, axis_b, radius, segments)
        points = []

        segments.times do |index|
          angle = (Math::PI * 2.0 * index) / segments

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
        direction = normalized(direction)
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

      def self.normalized(vector)
        VectorMath.normalized(vector, epsilon: EPSILON)
      end

      def self.to_point(value)
        return value if value.is_a?(Geom::Point3d)

        if value.respond_to?(:to_a)
          Geom::Point3d.new(value.to_a)
        else
          nil
        end
      rescue
        nil
      end
    end
  end
end
