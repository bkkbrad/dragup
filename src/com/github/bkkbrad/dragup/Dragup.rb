#!/usr/bin/env jruby
require 'java'
require 'yaml'
require 'logger'
require 'find'
#Dir.glob(File.join(File.dirname(__FILE__), "lib") + "/*.jar").each { |jar| require jar}
import com.jcraft.jsch.JSch
import org.jdesktop.swingworker.SwingWorker
import java.io.FileInputStream

#["ProgressMonitor", "TransferHandler","JSplitPane", "JTextField", "JPasswordField","JOptionPane", "JFrame", "JPanel", "JLabel", "JTextArea", "JButton", "JList", "BoxLayout", "JScrollPane", "JFileChooser", "JDialog"].each { |c| include_class "javax.swing.#{c}"}
import javax.swing.ProgressMonitor
import javax.swing.TransferHandler
import javax.swing.JSplitPane
import javax.swing.JTextField
import javax.swing.JPasswordField
import javax.swing.JOptionPane
import javax.swing.JFrame
import javax.swing.JPanel
import javax.swing.JLabel
import javax.swing.JTextArea
import javax.swing.JButton
import javax.swing.JList
import javax.swing.BoxLayout
import javax.swing.JScrollPane
import javax.swing.JFileChooser
import javax.swing.JDialog
["BorderLayout", "Frame"].each { |c| include_class "java.awt.#{c}" }
include_class "java.awt.datatransfer.DataFlavor"

class JTextAreaLogger
  def initialize(area)
    @area = area
  end

  def write(text)
    @area.text += text
  end

  def close

  end
end

class Dragup < JFrame
  attr_reader :host, :user, :remote, :known_hosts, :password, :model
  attr_writer :password
  def initialize(host, user, remote, known_hosts)
    @host = host
    @user = user
    @remote = remote
    @known_hosts = known_hosts
     
    logger = JTextArea.new
    logger.editable = false
    @log = Logger.new(JTextAreaLogger.new(logger))
    @log.info "Upload log initialized"

    super("Upload Files to " + host)
    set_default_close_operation(javax.swing.WindowConstants::EXIT_ON_CLOSE)

    panel = JPanel.new() 
    panel.layout = BorderLayout.new
    add(panel)

    @model = javax.swing.DefaultListModel.new
    list = JList.new(@model)
    list.setTransferHandler(FileListTransferHandler.new)

    @fc = JFileChooser.new;
    @fc.multi_selection_enabled = true 
    
    add_button = JButton.new "Add"
    add_button.add_action_listener do |e| 
      val = @fc.show_dialog(self, "Add File")
      if val == JFileChooser::APPROVE_OPTION
        files = @fc.selected_files
        index = @model.size
        @fc.selected_files.each do |f|
          index = add_path(index, f.path)
        end
      end
    end

    remove_button = JButton.new "Remove"
    remove_button.add_action_listener do |e|
      list.selected_indices.to_a.reverse.each { |i| @model.remove_element_at(i) }
    end
    
    button_panel = JPanel.new
    upload_button = JButton.new "Upload"
    upload_button.add_action_listener do |e|
      unless @password
        ulabel = JLabel.new("User:")
        user_box = JTextField.new(@user)
        plabel = JLabel.new("Password:")
        jpf = JPasswordField.new;
        val = JOptionPane.showConfirmDialog(self, [ulabel, user_box, plabel, jpf].to_java, "Login information", JOptionPane::OK_CANCEL_OPTION);
        break unless val == JOptionPane::OK_OPTION
        @user = user_box.text.strip
        @password = ""
        jpf.password.each { |c| @password << c }
      end
      
      f = nil
      pm = ProgressMonitor.new(self, "Transfering files", nil, 0, @model.size())
      button_panel.components.each { |c| c.enabled = false }
      task = UploadTask.new(self, pm, @log)
      task.add_property_change_listener do |event|
        if (event.property_name == "state") && (pm.canceled? || task.done?)
          button_panel.components.each { |c| c.enabled = true }
        end
      end
      task.execute
    end

    panel.add(JLabel.new("Files to upload:"), BorderLayout::NORTH)

    cpanel = JSplitPane.new(JSplitPane::VERTICAL_SPLIT)
    cpanel.add(JScrollPane.new(list))
    cpanel.add(JScrollPane.new(logger))

    [add_button, remove_button, upload_button].each { |b| button_panel.add(b) }

    panel.add(button_panel, BorderLayout::SOUTH)
    panel.add(cpanel)
    set_extended_state(get_extended_state | JFrame::MAXIMIZED_BOTH)
  end

  def self.absolute_path(path)
    File.expand_path(path, File.dirname(__FILE__))
  end
  
  def add_path(index, base)
    Find.find(File.expand_path(base)) do |path|
      if FileTest.file?(path)
        file_to_add = java.io.File.new(path)
        if !@model.contains(file_to_add)
          @model.add(index, file_to_add )
          index += 1
        end
      end
    end
    index
  end
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
          index = Dragup::add_path(model, index, file.path)
        end
      end
    end
    return true
  end
end


class UploadTask < SwingWorker 
  def initialize(dragup, pm, log = Logger.new(STDOUT))
    @dragup = dragup
    @pm = pm
    @log = log
    super()
  end

  def doInBackground
    f = nil
    begin
      @log.info "Connecting to host #{@dragup.host} as #{@dragup.user}..."
      jsch = JSch.new
      session = jsch.get_session(@dragup.user, @dragup.host);
      session.password = @dragup.password
      jsch.known_hosts = @dragup.known_hosts
      session.connect
      channel = session.open_channel("sftp")
      channel.connect
      @log.info "Connected."
      (0...@dragup.model.size()).each do |i|
        @pm.set_progress(i)
        if @pm.canceled?
          @pm.close
          raise "Transfer cancelled"
        end
        f = @dragup.model.get(0)
        remote_name = File.join(@dragup.remote, File.basename(f.path))
        @log.info "Transferring #{f} to #{remote_name}"
        channel.put(FileInputStream.new(f.path), remote_name)
        @dragup.model.remove_element_at(0)
      end
      @log.info "Finished uploading files."
    #rescue com.jcraft.jsch.JSchException
    #  @log.error "Error authenticating; check user name and password/"
    rescue Exception  
      if $!.message =~ /Auth fail/
        error_string = "Authentication failure."
        @dragup.password = nil
      elsif f
        error_string = "Error uploading file \"#{f}\": #{$!.message}"
      else
        error_string = "Error connecting: #{$!.message}" 
      end
      @log.error(error_string)
    ensure
      @pm.close if @pm
    end
    @log.info "Closing connection."
    channel.exit if channel
    session.disconnect if session
  end
end

def file_contents(path)
  com.github.bkkbrad.dragup.Dragup.java_class.resource_as_string(path)
end

CONFIG = YAML::load(file_contents("/config.yaml"))
host = CONFIG['host']
user = CONFIG['user']
remote = CONFIG['remote-dir']
known_hosts = java.io.ByteArrayInputStream.new(file_contents("/known_hosts").to_java_bytes)
dragup = Dragup.new(host, user, remote, known_hosts)
index = 0
ARGV.each do |arg|
  index = dragup.add_path(index, arg)
end
dragup.show
