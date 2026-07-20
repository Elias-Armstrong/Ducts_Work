module DuctExtension
  module Toolbar
    TOOLBAR_NAME = "Simple Duct"

    def self.create
      return if @created

      toolbar = UI::Toolbar.new(TOOLBAR_NAME)

      draw_command = UI::Command.new("Draw Orthogonal Duct") {
        Sketchup.active_model.select_tool(DuctExtension::Tool::DuctTool.new)
      }

      draw_command.tooltip = "Draw Orthogonal Duct"
      draw_command.status_bar_text = "Draw round or rectangular duct using orthogonal snap routing."

      reducer_command = UI::Command.new("Add Increaser / Reducer") {
        Sketchup.active_model.select_tool(DuctExtension::Tool::ReducerTool.new)
      }

      reducer_command.tooltip = "Add Increaser / Reducer"
      reducer_command.status_bar_text = "Click an open duct end and enter the new size."

      clear_command = UI::Command.new("Clear Duct Data") {
        result = UI.messagebox(
          "This will clear stored duct connection data from this model.\n\n" \
          "The 3D geometry will remain, but existing ducts will no longer snap as editable duct pieces.\n\n" \
          "Continue?",
          MB_YESNO
        )

        next unless result == IDYES

        network = DuctExtension.network_for_model(Sketchup.active_model)

        DuctExtension::Services::NetworkClearService.clear_model_data(
          Sketchup.active_model,
          network
        )

        UI.messagebox("Duct data cleared. Geometry was left unchanged.")
      }

      clear_command.tooltip = "Clear Duct Data"
      clear_command.status_bar_text = "Clear duct metadata while leaving geometry in place."

      toolbar.add_item(draw_command)
      toolbar.add_item(reducer_command)
      toolbar.add_item(clear_command)

      toolbar.restore

      @created = true
      toolbar
    rescue => error
      puts "DuctExtension::Toolbar.create failed: #{error.message}"
      nil
    end
  end
end
