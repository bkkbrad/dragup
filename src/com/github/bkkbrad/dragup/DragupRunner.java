package com.github.bkkbrad.dragup;

import org.jruby.Main;

public class DragupRunner {
  public static void main(String[] args) throws Exception {
    String[] args2 = new String[2 + args.length];
    if (args.length > 0) {
      System.arraycopy(args, 0, args2, 2, args.length);
    }
    args2[0] = "-e";
    args2[1] = "require 'dragup.rb'";
    Main.main(args2);
  }
}
