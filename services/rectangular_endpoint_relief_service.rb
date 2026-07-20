module DuctExtension
  module Services
    module RectangularEndpointReliefService
      # Kept as a tiny compatibility service for the rebuilt extension.
      #
      # The old project had several endpoint-relief experiments to hide
      # rectangular seam artifacts. In the cleaned orthogonal version, rectangular
      # ducts are built as clean open-ended prisms with explicit frame axes, so
      # this service intentionally does not mutate geometry.
      #
      # It remains available so older calls/requires do not break.

      def self.apply(*)
        true
      end

      def self.apply_to_piece(*)
        true
      end

      def self.relieve(*)
        true
      end
    end
  end
end
