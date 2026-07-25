module DuctExtension
  module Toolbar
    TOOLBAR_NAME = "Simple Duct"

    def self.create
      return if @created

      toolbar = UI::Toolbar.new(TOOLBAR_NAME)

      draw_command = UI::Command.new("Draw Orthogonal Duct") { UIActions.draw_duct }
      draw_command.tooltip = "Draw Orthogonal Duct"
      draw_command.status_bar_text = "Draw round or rectangular duct using orthogonal snap routing."

      resize_command = UI::Command.new("Resize Selected Duct Pieces") { UIActions.resize_selection }
      resize_command.tooltip = "Resize Selected Duct Pieces"
      resize_command.status_bar_text = "Resize selected duct pieces and add boundary reducers/increasers where needed."

      reducer_command = UI::Command.new("Add Increaser / Reducer") { UIActions.add_reducer }
      reducer_command.tooltip = "Add Increaser / Reducer"
      reducer_command.status_bar_text = "Click an open duct end and enter the new size."

      clear_command = UI::Command.new("Clear Duct Data") { UIActions.clear_duct_data }
      clear_command.tooltip = "Clear Duct Data"
      clear_command.status_bar_text = "Clear duct metadata while leaving geometry in place."

      [draw_command, resize_command, reducer_command, clear_command].each { |command| toolbar.add_item(command) }
      toolbar.restore

      @created = true
      toolbar
    rescue => error
      puts "DuctExtension::Toolbar.create failed: #{error.message}"
      nil
    end
  end
end
