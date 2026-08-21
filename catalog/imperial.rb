module DuctExtension
  module Catalog
    # Imperial Manufacturing Group — selected 2026 galvanized residential HVAC
    # product families that map directly onto Simple Duct's existing semantic
    # component types. Gauge/packaged-length variants are intentionally collapsed
    # to one representative real SKU per modeling choice. Specialty oval systems,
    # plenums, cleats, roof products, reverse/shoe-boot elbows, and other shapes
    # that would require new semantics are deliberately excluded.
    module Imperial
      KEY = :imperial
      NAME = "Imperial"
      CATALOG_DOCUMENT = "Imperial 2026 Galvanized Duct, Pipe & Fittings Catalogue"

      Product = MasterFlow::Product

      module_function

      def product(**kwargs)
        Product.new(**kwargs.merge(
          catalog_key: KEY,
          catalog_name: NAME,
          catalog_document: CATALOG_DOCUMENT
        ))
      end

      # ---- STRAIGHT ROUND DUCT -----------------------------------------------
      # Imperial publishes many lengths/gauges. As in Master Flow mode, these are
      # collapsed by connector size so a modeled run may be any length without
      # fake stock-section joints.
      ROUND_PIPES = [
        ["GV0352",  3.0],
        ["GV1209",  4.0],
        ["GV1210",  5.0],
        ["GV1236",  6.0],
        ["GV0401",  7.0],
        ["GV0412",  8.0],
        ["GV0420",  9.0],
        ["GV0427", 10.0],
        ["GV0436", 12.0],
        ["GV1186", 14.0]
      ].map do |sku, diameter|
        product(
          sku: sku,
          family: :pipe,
          name: "#{diameter.to_i}\" Galvanized Round Pipe",
          shape: :round,
          diameter: diameter,
          style: :snap_lock,
          notes: "Representative Imperial round-pipe SKU for this diameter; packaged length/gauge variants are collapsed for continuous modeling."
        )
      end.freeze

      # ---- STRAIGHT RECTANGULAR DUCT -----------------------------------------
      RECTANGULAR_PIPES = [
        # Residential stack duct.
        ["GV1306", 10.0, 2.25, :stack_duct],
        ["GV1318", 12.0, 2.25, :stack_duct],
        ["GV0220", 10.0, 3.25, :stack_duct],
        ["GV1184", 12.0, 3.25, :stack_duct],
        # Common 8-inch-deep trunk duct with S & drive cleats included.
        ["GV0233",  8.0, 8.0, :trunk_duct],
        ["GV0234", 10.0, 8.0, :trunk_duct],
        ["GV0235", 12.0, 8.0, :trunk_duct],
        ["GV0236", 14.0, 8.0, :trunk_duct],
        ["GV0237", 16.0, 8.0, :trunk_duct],
        ["GV0238", 18.0, 8.0, :trunk_duct],
        ["GV0239", 20.0, 8.0, :trunk_duct],
        ["GV0240", 22.0, 8.0, :trunk_duct],
        ["GV0241", 24.0, 8.0, :trunk_duct]
      ].map do |sku, width, height, style|
        product(
          sku: sku,
          family: :pipe,
          name: "#{width.to_s.sub('.0','')}\" x #{height.to_s.sub('.0','')}\" #{style == :stack_duct ? 'Stack' : 'Trunk'} Duct",
          shape: :rectangular,
          width: width,
          height: height,
          style: :half_section,
          notes: "Representative Imperial rectangular-duct SKU; modeled run length is unrestricted."
        )
      end.freeze

      # ---- ROUND ADJUSTABLE ELBOWS -------------------------------------------
      # Imperial's 90-degree adjustable elbow family is adjustable from 0°-90°.
      # One representative gauge/SKU is retained for each diameter.
      ROUND_ELBOWS = [
        ["GV0282",  3.0],
        ["GV0286",  4.0],
        ["GV0291",  5.0],
        ["GV0296",  6.0],
        ["GV0300",  7.0],
        ["GV0303",  8.0],
        ["GV0306",  9.0],
        ["GV0309", 10.0],
        ["GV0312", 12.0],
        ["GV0314", 14.0]
      ].map do |sku, diameter|
        product(
          sku: sku,
          family: :elbow,
          name: "#{diameter.to_i}\" 90° Adjustable Elbow",
          shape: :round,
          diameter: diameter,
          angle_degrees: 90.0,
          style: :four_gore_adjustable,
          notes: "Imperial adjustable round elbow; catalog-authoritative nominal diameter and 0°-90° adjustment range. Physical envelope is modeled from the shared fabricated-elbow renderer where no published overall is loaded."
        )
      end.freeze

      # ---- RECTANGULAR 45° / 90° ELBOWS -------------------------------------
      rectangular_elbows = []

      # 3-1/4 x 10 stack duct has both flat/side 45° and 90° products.
      rectangular_elbows.concat([
        ["GV0060", 10.0, 3.25, 90.0, :short_way_miter, "Flat"],
        ["GV0048", 10.0, 3.25, 45.0, :short_way_miter, "Flat"],
        ["GV0092", 10.0, 3.25, 90.0, :long_way_miter,  "Side"],
        ["GV0080", 10.0, 3.25, 45.0, :long_way_miter,  "Side"],
        ["GV1147", 12.0, 3.25, 90.0, :short_way_miter, "Flat"]
      ])

      # 8-inch-deep trunk duct fixed elbows. Product lists are kept only where
      # Imperial explicitly publishes the size/angle combination.
      flat_90 = {
        8=>"GV0065", 10=>"GV0066", 12=>"GV0067", 14=>"GV0068", 16=>"GV0069",
        18=>"GV0070", 20=>"GV0071", 22=>"GV0072", 24=>"GV0073"
      }
      flat_45 = {
        10=>"GV0051", 12=>"GV0052", 14=>"GV0053", 16=>"GV0054",
        18=>"GV0055", 20=>"GV0056", 24=>"GV0058"
      }
      side_90 = {
        8=>"GV0096", 10=>"GV0097", 12=>"GV0098", 14=>"GV0099", 16=>"GV0100",
        18=>"GV0101", 20=>"GV0102", 22=>"GV0103", 24=>"GV0104"
      }
      side_45 = {
        8=>"GV0082", 10=>"GV0083", 12=>"GV0084", 14=>"GV0085", 16=>"GV0086",
        18=>"GV0087", 20=>"GV0088", 24=>"GV0090"
      }

      flat_90.each  { |w, sku| rectangular_elbows << [sku, w.to_f, 8.0, 90.0, :short_way_miter, "Flat"] }
      flat_45.each  { |w, sku| rectangular_elbows << [sku, w.to_f, 8.0, 45.0, :short_way_miter, "Flat"] }
      side_90.each  { |w, sku| rectangular_elbows << [sku, w.to_f, 8.0, 90.0, :long_way_miter,  "Side"] }
      side_45.each  { |w, sku| rectangular_elbows << [sku, w.to_f, 8.0, 45.0, :long_way_miter,  "Side"] }

      RECTANGULAR_ELBOWS = rectangular_elbows.map do |sku, width, height, angle, style, orientation|
        product(
          sku: sku,
          family: :elbow,
          name: "#{width.to_s.sub('.0','')}\" x #{height.to_s.sub('.0','')}\" #{angle.to_i}° #{orientation} Elbow",
          shape: :rectangular,
          width: width,
          height: height,
          angle_degrees: angle,
          style: style,
          notes: "Fixed Imperial rectangular #{orientation.downcase} elbow at #{angle.to_i}°."
        )
      end.freeze

      # ---- FULL-FLOW TEES -----------------------------------------------------
      ROUND_TEES = [
        ["GV0912",  3.0],
        ["GV0913",  4.0],
        ["GV0916",  5.0],
        ["GV0920",  6.0],
        ["GV0896",  7.0],
        ["GV0924",  8.0],
        ["GV0925", 10.0],
        ["GV1255", 12.0]
      ].map do |sku, diameter|
        product(
          sku: sku,
          family: :tee,
          name: "#{diameter.to_i}\" Equal Round Tee",
          shape: :round,
          diameter: diameter,
          branch_diameter: diameter,
          outlet_diameter: diameter,
          angle_degrees: 90.0,
          style: :full_flow_tee,
          notes: "Equal-size Imperial 90-degree tee. Reducing tee variants are intentionally represented using a tee plus a stocked reducer rather than adding asymmetric tee semantics."
        )
      end.freeze

      # ---- FULL-FLOW WYES -----------------------------------------------------
      ROUND_WYES = [
        ["GV0983",  3.0],
        ["GV0984",  4.0],
        ["GV0989",  5.0],
        ["GV0997",  6.0],
        ["GV1004",  7.0],
        ["GV1008",  8.0],
        ["GV1192", 10.0]
      ].map do |sku, diameter|
        product(
          sku: sku,
          family: :wye,
          name: "#{diameter.to_i}\" Equal Full-Flow Wye",
          shape: :round,
          diameter: diameter,
          outlet_diameter: diameter,
          branch_diameter: diameter,
          angle_degrees: 45.0,
          style: :equal_lateral,
          notes: "Equal-size Imperial full-flow wye. Asymmetric Imperial wyes are excluded until Simple Duct has independent straight-outlet and branch-diameter semantics in the end-wye workflow."
        )
      end.freeze

      # ---- INLINE SADDLES -----------------------------------------------------
      TEE_SADDLES = [
        ["GV1426", 3.0],
        ["GV1056", 6.0]
      ].map do |sku, branch|
        product(
          sku: sku,
          family: :tee_saddle,
          name: "#{branch.to_i}\" Tee Saddle",
          shape: :round,
          diameter: branch,
          branch_diameter: branch,
          angle_degrees: 90.0,
          style: :tee_saddle_equal_or_larger,
          notes: "Imperial tee saddle for an existing round main of equal or larger diameter."
        )
      end.freeze

      WYE_SADDLES = [
        ["GV0978", 3.0],
        ["GV0979", 4.0],
        ["GV0980", 5.0],
        ["GV0981", 6.0],
        ["GV0982", 8.0]
      ].map do |sku, branch|
        product(
          sku: sku,
          family: :wye_saddle,
          name: "#{branch.to_i}\" Wye Saddle",
          shape: :round,
          diameter: branch,
          branch_diameter: branch,
          angle_degrees: 45.0,
          style: :wye_saddle,
          notes: "Imperial 45-degree wye saddle for an existing round main of equal or larger diameter."
        )
      end.freeze

      # ---- ROUND REDUCERS / INCREASERS ---------------------------------------
      # Direct Imperial products only. Length is not claimed exact when the
      # public catalog page does not publish an overall; the transition service
      # therefore uses its normal derived/default fitting length.
      ROUND_REDUCERS = [
        ["GV0779",  4.0,  3.0],
        ["GV0780",  5.0,  3.0],
        ["GV0781",  5.0,  4.0],
        ["GV2002",  6.0,  3.0],
        ["GV1199",  6.0,  4.0],
        ["GV1922",  6.0,  5.0],
        ["GV1201",  7.0,  5.0],
        ["GV1202",  7.0,  6.0],
        ["GV1268",  8.0,  5.0],
        ["GV0821",  8.0,  6.0],
        ["GV1204",  8.0,  7.0],
        ["GV1269",  9.0,  6.0],
        ["GV1203",  9.0,  8.0],
        ["GV1245", 10.0,  6.0],
        ["GV0830", 10.0,  8.0],
        ["GV1421", 12.0, 10.0],
        ["GV0836", 14.0, 12.0]
      ].map do |sku, large, small|
        product(
          sku: sku,
          family: :transition,
          name: "#{large.to_i}\" to #{small.to_i}\" Round Increaser / Reducer",
          shape: :round,
          diameter: large,
          branch_diameter: small,
          style: :hemmed_reducer,
          notes: "Direct Imperial reducer/increaser. Public catalog connector sizes are authoritative; modeled fitting length is derived when an overall is not published."
        )
      end.freeze

      # ---- UNIVERSAL REGISTER BOOTS ------------------------------------------
      REGISTER_BOXES = [
        ["GV0683",  10.0, 3.25, 4.0],
        ["GV0692",  10.0, 3.25, 5.0],
        ["GV0702",  10.0, 3.25, 6.0],
        ["GV0709",  10.0, 3.25, 7.0],
        ["GV0715",  10.0, 3.25, 8.0],
        ["GV0685",  10.0, 4.0,  4.0],
        ["GV0694",  10.0, 4.0,  5.0],
        ["GV0704",  10.0, 4.0,  6.0],
        ["GV0710",  10.0, 4.0,  7.0],
        ["GV0695",  12.0, 4.0,  5.0],
        ["GV0705",  12.0, 4.0,  6.0],
        ["GV0711",  12.0, 4.0,  7.0],
        ["GV0707",  10.0, 6.0,  6.0],
        ["GV0708",  12.0, 6.0,  6.0],
        ["GV0679",  10.0, 2.25, 4.0],
        ["GV0680",  12.0, 2.25, 4.0],
        ["GV0699",  12.0, 2.25, 6.0]
      ].map do |sku, width, height, diameter|
        product(
          sku: sku,
          family: :register_box,
          name: "#{width.to_s.sub('.0','')}\" x #{height.to_s.sub('.0','')}\" to #{diameter.to_i}\" Universal Boot",
          shape: :mixed,
          diameter: diameter,
          width: width,
          height: height,
          style: :straight_register_box,
          notes: "Imperial in-line round-duct-to-register/grille universal boot."
        )
      end.freeze

      # ---- END COVERS ---------------------------------------------------------
      ROUND_END_COVERS = [
        ["GV0721",  3.0], ["GV0722",  4.0], ["GV0723",  5.0], ["GV0724",  6.0],
        ["GV0725",  7.0], ["GV0726",  8.0], ["GV0727",  9.0], ["GV0728", 10.0],
        ["GV0729", 12.0], ["GV0730", 14.0]
      ].map do |sku, diameter|
        product(
          sku: sku,
          family: :end_cover,
          name: "#{diameter.to_i}\" Round End Cap",
          shape: :round,
          diameter: diameter,
          style: :round_duct_cap,
          notes: "Imperial big-end/no-crimp round end cap selected as the representative termination product."
        )
      end

      RECTANGULAR_END_COVERS = begin
        rows = [
          ["GV0022", 10.0, 3.25],
          ["GV0023", 12.0, 3.25],
          ["GV0030",  8.0, 8.0], ["GV0031", 10.0, 8.0], ["GV0032", 12.0, 8.0],
          ["GV0033", 14.0, 8.0], ["GV0034", 16.0, 8.0], ["GV0035", 18.0, 8.0],
          ["GV0036", 20.0, 8.0], ["GV0037", 22.0, 8.0], ["GV0038", 24.0, 8.0]
        ]
        rows.map do |sku, width, height|
          product(
            sku: sku,
            family: :end_cover,
            name: "#{width.to_s.sub('.0','')}\" x #{height.to_s.sub('.0','')}\" Blind End Cap",
            shape: :rectangular,
            width: width,
            height: height,
            style: :rectangular_duct_cap,
            notes: "Imperial blind end cap for rectangular duct."
          )
        end
      end

      END_COVERS = (ROUND_END_COVERS + RECTANGULAR_END_COVERS).freeze

      PRODUCTS = (
        ROUND_PIPES + RECTANGULAR_PIPES +
        ROUND_ELBOWS + RECTANGULAR_ELBOWS +
        ROUND_TEES + ROUND_WYES + TEE_SADDLES + WYE_SADDLES +
        ROUND_REDUCERS + REGISTER_BOXES + END_COVERS
      ).freeze

      def products
        PRODUCTS
      end
    end
  end
end
