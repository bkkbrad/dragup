#!/usr/bin/env jruby
require 'java'
require 'yaml'
require 'find'
CONFIG = YAML::load(File.read(File.join(File.dirname(__FILE__), 'config.yaml')))
$host = CONFIG['host']
$user = CONFIG['user']
$remote = CONFIG['remote-dir']
$password = nil

["TransferHandler","JSplitPane", "JTextField", "JPasswordField","JOptionPane", "JFrame", "JPanel", "JLabel", "JTextArea", "JButton", "JList", "BoxLayout", "JScrollPane", "JFileChooser", "JDialog"].each { |c| include_class "javax.swing.#{c}"}
["BorderLayout", "Frame"].each { |c| include_class "java.awt.#{c}" }
include_class "java.awt.datatransfer.DataFlavor"

#TODO do actual file transfer
def transfer(f)
  p [f, $host, $user, $remote]
  true
end
frame = JFrame.new("Upload Files")
frame.defaultCloseOperation=javax.swing.WindowConstants::EXIT_ON_CLOSE
panel = JPanel.new() 
panel.layout = BorderLayout.new
frame.add(panel)

model = javax.swing.DefaultListModel.new

def add_path(model, index, base)
  Find.find(File.expand_path(base)) do |path|
    if FileTest.file?(path)
      file_to_add = java.io.File.new(path)
      if !model.contains(file_to_add)
        model.add(index, file_to_add )
        index += 1
      end
    end
  end
  index
end

list = JList.new(model)
index = 0
ARGV.each do |arg|
  index = add_path(model, index, arg)
end

class FileListTransferHandler < TransferHandler
  def canImport(comp, transfer_flavors)
    transfer_flavors.each { |flav| return true if flav.equals(DataFlavor::javaFileListFlavor) }
    false
  end

  def importData(comp, transferable)
    return false unless canImport(comp, transferable.transfer_data_flavors)
    model = comp.model
    index = comp.get_selected_index
    max = model.size
    if index < 0
      index = max
    else
      index += 1
      index = max if index > max
    end

    transferable.transfer_data_flavors.each do |flavor|
      if flavor.equals(DataFlavor::javaFileListFlavor)
        transferable.get_transfer_data(flavor).each do |file|
          index = add_path(model, index, file.path)
        end
      end
    end
    return true
  end
end
list.setTransferHandler(FileListTransferHandler.new)

fc = JFileChooser.new;
fc.multi_selection_enabled = true 

$logger = JTextArea.new
$logger.text="Upload Log"
$logger.editable = false
def log(text)
  $logger.text += "\n" + text
end

add_button = JButton.new "Add"
add_button.add_action_listener do |e| 
  val = fc.show_dialog(frame, "Add File")
  if val == JFileChooser::APPROVE_OPTION
    files = fc.selected_files
    index = model.size
    fc.selected_files.each do |f|
      index = add_path(model, index, f.path)
    end
  else
    p "ignore"
  end
end

remove_button = JButton.new "Remove"
remove_button.add_action_listener do |e|
  list.selected_indices.to_a.reverse.each { |i| model.remove_element_at(i) }
end

upload_button = JButton.new "Upload"
upload_button.add_action_listener do |e|
  unless $password
    hlabel = JLabel.new("Host:")
    host_box = JTextField.new($host)
    ulabel = JLabel.new("User:")
    user_box = JTextField.new($user)
    plabel = JLabel.new("Password:")
    jpf = JPasswordField.new;
    rlabel = JLabel.new("Remote directory:")
    remote_box = JTextField.new($remote)
    val = JOptionPane.showConfirmDialog(frame, [hlabel, host_box, ulabel, user_box, plabel, jpf, rlabel, remote_box].to_java, "Login information", JOptionPane::OK_CANCEL_OPTION);
    break unless val == JOptionPane::OK_OPTION
    $host = host_box.text
    $user = user_box.text
    $remote = remote_box.text
    $password = jpf.password
  end
  (0...model.size()).each do |i|
    f = model.get(0)
    log "Transfering #{f}"
    unless transfer(f)
      error_string = "Error uploading file \"#{f}\"."
      JOptionPane.showMessageDialog(frame,"Transfer Error", error_string, JOptionPane::ERROR_MESSAGE)
      log error_string
      break
    else
      model.remove_element_at(0)
    end
  end
end

panel.add(JLabel.new("Files to upload:"), BorderLayout::NORTH)

cpanel = JSplitPane.new(JSplitPane::VERTICAL_SPLIT)
cpanel.add(JScrollPane.new(list))
cpanel.add(JScrollPane.new($logger))

button_panel = JPanel.new
[add_button, remove_button, upload_button].each { |b| button_panel.add(b) }

panel.add(button_panel, BorderLayout::SOUTH)
panel.add(cpanel)
#frame.pack
frame.extended_state = frame.extended_state | JFrame::MAXIMIZED_BOTH
frame.show
