module DuctExtension
  module Model
    class SpatialPortIndex
      DEFAULT_CELL_SIZE = 12.0

      def initialize(cell_size = DEFAULT_CELL_SIZE)
        @cell_size = cell_size.to_f
        @cell_size = DEFAULT_CELL_SIZE if @cell_size <= 0.0
        @cells = {}
      end

      def clear
        @cells.clear
      end

      def rebuild(ports)
        clear

        Array(ports).each do |port|
          add(port)
        end
      end

      def add(port)
        return unless port
        return unless port.respond_to?(:point)

        key = cell_key_for_point(port.point)
        @cells[key] ||= []
        @cells[key] << port unless @cells[key].include?(port)
      end

      def remove(port)
        return unless port
        return unless port.respond_to?(:point)

        key = cell_key_for_point(port.point)
        return unless @cells[key]

        @cells[key].delete(port)
        @cells.delete(key) if @cells[key].empty?
      end

      def nearby(point, radius)
        radius = radius.to_f
        return [] if radius < 0.0

        center_key = cell_key_for_point(point)
        cell_radius = (radius / @cell_size).ceil + 1

        results = []

        (-cell_radius..cell_radius).each do |dx|
          (-cell_radius..cell_radius).each do |dy|
            (-cell_radius..cell_radius).each do |dz|
              key = [
                center_key[0] + dx,
                center_key[1] + dy,
                center_key[2] + dz
              ]

              next unless @cells[key]

              @cells[key].each do |port|
                next unless port && port.respond_to?(:point)
                next if port.point.distance(point) > radius

                results << port
              end
            end
          end
        end

        results
      end

      private

      def cell_key_for_point(point)
        [
          (point.x / @cell_size).floor,
          (point.y / @cell_size).floor,
          (point.z / @cell_size).floor
        ]
      end
    end
  end
end
