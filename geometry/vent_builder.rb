module DuctExtension
  module Geometry
    module VentBuilder
      EPSILON = 0.000001

      ROUND_SEGMENTS = 40
      GRILLE_RINGS = 5
      GRILLE_SPOKES = 12

      PLATE_THICKNESS_FACTOR = 0.045
      SLOT_RECESS_FACTOR = 0.018

      END_COVER_OVERSIZE_FACTOR = 1.22
      END_COVER_THICKNESS_FACTOR = 0.10
      END_COVER_DOME_FACTOR = 0.08

      REGISTER_BUMP_FACTOR = 0.12

      # Register connector tuning.
      #
      # Goal:
      # - Keep the nice previous front-face register aesthetic.
      # - Fill the visible gap between register and pipe.
      # - Do NOT punch through the far side of round duct.
      #
      # This builds a shallow saddle connector behind the register. On round
      # ducts, the hidden back corners are pulled inward according to pipe
      # curvature, then clamped so the connector only bites into the near side.
      REGISTER_SADDLE_MIN_BITE_FACTOR = 0.055
      REGISTER_SADDLE_MAX_DEPTH_FACTOR = 0.42
      REGISTER_SADDLE_MIN_DEPTH = 0.08

    end
  end
end
require_relative 'vent/side_register_geometry'
require_relative 'vent/end_cover_geometry'
require_relative 'vent/detail_geometry'
