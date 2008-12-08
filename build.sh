#!/bin/bash
rm -rf build/* dist/*
#javac -sourcepath src -cp lib/jruby-complete-1.1.5.jar:lib/jsch-0.1.40.jar:lib/swing-worker-1.2.jar -d build src/com/github/bkkbrad/dragup/DragupRunner.java
jrubyc -d src -t build src/com/github/bkkbrad/dragup/Dragup.rb
jar cvf dist/dragup.jar config.yaml known_hosts -C build/ . 
jarsigner -keystore myKeystore dist/dragup.jar myself
