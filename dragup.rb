#!/usr/bin/env jruby
require 'java'
require 'yaml'
require 'find'
Dir.glob(File.join(File.dirname(__FILE__), "lib") + "/*.jar").each { |jar| require jar}
import com.jcraft.jsch.JSch
import org.jdesktop.swingworker.SwingWorker
["ProgressMonitor", "TransferHandler","JSplitPane", "JTextField", "JPasswordField","JOptionPane", "JFrame", "JPanel", "JLabel", "JTextArea", "JButton", "JList", "BoxLayout", "JScrollPane", "JFileChooser", "JDialog"].each { |c| include_class "javax.swing.#{c}"}
["BorderLayout", "Frame"].each { |c| include_class "java.awt.#{c}" }
include_class "java.awt.datatransfer.DataFlavor"

class Dragup < JFrame
  def initialize(host, user, remote, known_hosts)
    @host = host
    @user = user
    @remote = remote
    @known_hosts = known_hosts
  
    super("Upload Files to " + host)
    default_close_operation = javax.swing.WindowConstants::EXIT_ON_CLOSE

    panel = JPanel.new() 
    panel.layout = BorderLayout.new
    add(panel)

    @model = javax.swing.DefaultListModel.new
  end

  def absolute_path(path)
    File.expand_path(path, File.dirname(__FILE__))
  end
  
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
end

CONFIG = YAML::load(File.read(absolute_path('config.yaml')))
$host = CONFIG['host']
$user = CONFIG['user']
$remote = CONFIG['remote-dir']
$known_hosts = absolute_path(CONFIG['known-hosts'])
$password = nil




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

class UploadTask < SwingWorker 
  def initialize(model, frame, pm)
    @model = model
    @frame = frame
    @pm = pm
    super()
  end

  def doInBackground
    begin
      log "Connecting to host #{$host} as #{$user}..."
      jsch = JSch.new
      session = jsch.get_session($user, $host);
      session.password = $password
      jsch.known_hosts = $known_hosts
      session.connect
      channel = session.open_channel("sftp")
      channel.connect
      log "Connected."
      (0...@model.size()).each do |i|
        @pm.set_progress(i)
        puts "prgress" 
        if @pm.is_canceled
          @pm.close
          raise "Transfer cancelled"
        end
        puts "not cancelled"
        f = @model.get(0)
        remote_name = File.join($remote, File.basename(f.path))
        log "Transferring #{f} to #{remote_name}"
        channel.put(java.io.FileInputStream.new(f.path), remote_name)
        @model.remove_element_at(0)
      end
      log "Finished uploading files."
      @pm.close
    rescue Exception => e 
      if f
        error_string = "Error uploading file \"#{f}\":\n" + e.message
      else
        error_string = "Error connecting:\n" + e.message
      end
      log error_string
      JOptionPane.showMessageDialog(@frame,"Transfer Error", error_string, JOptionPane::ERROR_MESSAGE)
    end
    log "Closing connection."
    channel.exit if channel
    session.disconnect if session
  end
end
upload_button = JButton.new "Upload"
upload_button.add_action_listener do |e|
  unless $password
    ulabel = JLabel.new("User:")
    user_box = JTextField.new($user)
    plabel = JLabel.new("Password:")
    jpf = JPasswordField.new;
    val = JOptionPane.showConfirmDialog(frame, [ulabel, user_box, plabel, jpf].to_java, "Login information", JOptionPane::OK_CANCEL_OPTION);
    break unless val == JOptionPane::OK_OPTION
    $user = user_box.text.strip
    $password = ""
    jpf.password.each { |c| $password << c }
  end
  
  f = nil
  pm = ProgressMonitor.new(frame, "Transfering files", nil, 0, model.size())
  task = UploadTask.new(model, frame, pm)
  task.execute
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
