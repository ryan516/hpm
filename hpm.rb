#!/usr/bin/env ruby

#The MIT License (MIT)

#Copyright (c) <2013> <Brian Manderville; Brian McCoskey; Descent|OS>

#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions

#The above copyright notice and this permission notice shall be included in
#all copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#THE SOFTWARE.

require 'fileutils'

def helpPage()
    # A friendly little help page. This displays to the user whenever a
    # user chooses the "help" commmand, or any invalid command.
    puts "Usage"
    puts " hpm (options) {package}"
    puts ""
    puts "Options include:"
    puts " install        :   install selected binary package(s) from repository"
    puts " source-instal  :   install selected package(s) from source"
    puts " local-install  :   install selected local package(s)"
    puts " remove         :   remove selected package(s)"
    puts " clean          :   clean the cache"
    puts " update         :   update the cache" 
    puts " upgrade        :   upgrade current packages"
    puts " help           :   view this help page"
    puts ""
    return 0
end

def clean()
    # Cleans the cache by removing all files from /opt/hpm/tmp/
    puts "Cleaning Cache: "
    FileUtils::Verbose.rm_rf(Dir.glob("/opt/hpm/tmp/*"))
    puts "Cache Cleaned"
end

def test_mirror()
    # Verifies connectivity to the mirrors chosen by the user. The list of 
    # mirrors is stored in /etc/hpm/mirrors/mirror.lst, with each mirror
    # on their own line. Checks each mirror for a valid ping.
    f = File.open("/etc/hpm/mirrors/mirror.lst", "r")
    f.each_line { |line|

    tempstatus = `bash /bin/hpkg/resources/testmirror.sh #{line}` 
    status = tempstatus.split

    if status[-1] == "true" 
        puts "Connected to #{line}"
    elsif status[-1] == "false" 
        puts "Error Connecting to #{line}"
    else
        puts "Fail!"
    end
    } 
    f.close
end

def hpacmv(packageName, source, dest)
    # Move the package from the source (BIN_FILE from the .control file) 
    # to its destination (BIN_PATH from the .control file)
    FileUtils.cd("/opt/hpm/tmp/#{packageName}/")
    FileUtils.mv("/opt/hpm/tmp/#{packageName}/#{source}", dest)
end

def gethpac(packageName, current, total)
    # Download the package from the mirror
    databaseFile = File.open("/etc/hpm/pkginfo/hpmDatabase.info", "r")
    database = databaseFile.readlines
    databaseFile.close
    blocks = find_block(database)
    mirror = nil
    blocks.each_with_index do |block, index|
        i = block[0]
        endBlock = block[1]
        packageTest = block[2].scan(/HPKGNAME=(.+$)/)
        packageTest = packageTest.join
        if packageTest = packageName
            while i <= endBlock
                if not database[i] == nil
                    if database[i].include? "MIRROR="
                        mirror = database[i].scan(/MIRROR=(.+$)/)
                        mirror = mirror.join
                    end
                end
            i += 1
            end
        end
    end

    puts `wget -q -c -O /opt/hpm/tmp/#{packageName}.hpac #{mirror}/#{packageName}.hpac`

    puts "(#{current}/#{total}) Getting #{packageName}..."
    sha512check = `sha512sum /opt/hpm/tmp/#{packageName}.hpac`
    sha512check = sha512check.scan(/(.+)\  .+$/)
    sha512check = sha512check.join
    sha512check = sha512check.chomp
    sha512verify = nil
    blocks.each do |block|
        nameCheck = block[2].scan(/HPKGNAME=(.+$)/)
        nameCheck = nameCheck.join
        if nameCheck == packageName
            i = block[0]
            endBlock = block[1]
            while i <= endBlock
                if not database[i] == nil
                    if database[i].include?("SHA512SUM")
                        sha512verify = database[i].scan(/SHA512SUM=(.+$)/) 
                        sha512verify = sha512verify.join
                        sha512verify = sha512verify.chomp
                    end
                end
            i += 1
            end
        end
    end

    if not sha512check.eql? sha512verify
        puts "Bad sha512sum: #{packageName}\nRetrying..."
        FileUtils.rm("/opt/hpm/tmp/#{packageName}.hpac")
        gethpac(packageName, current, total)
    end
end

def checkFile( db_file, package )
    # Check whether or not the database contains the version of the package 
    # requested by the user. If so, return "true"
    File.open( db_file ) do |io|
    io.each {|line| line.chomp! ; return true if line.include? package}
    end
end

def exthpac(packageName)
    # Extract the contents from the packaeg.
    puts "Extracting #{packageName}..."
    puts `tar -C /opt/hpm/tmp/ -xjf /opt/hpm/tmp/#{packageName}.hpac`
end

def find_block(database)
    # Find a unique block for a package within the repository database
    # and return the start and endpoints of said block.
    
    blocklist = []
    namelist = []
    database.each_with_index do |line, databaseIndex|
        if not line == nil
            if line.include? "HPKGNAME="
                pkgname = line.chomp
                blocklist.push(databaseIndex)
                namelist.push(pkgname)
            end
        end
    end

    newlist = Array.new 

    blocklist.each_index do |databaseIndex|
        newlist << blocklist.slice(databaseIndex, 2)
        newlist[databaseIndex].push namelist[databaseIndex]
    end

    newlist.each_index do |index|
        if newlist[index].length == 2
            newlist[index].insert(1, database.length)
        elsif newlist[index].length == 3
            newlist[index][1] = newlist[index][1] - 1
        end
    end

    return newlist
end

def queue_check(database, packageName, packages)
    # check the dependency list of each file, for each
    # dependency, check if it is installed, if not, add
    # it to the list of files to be installed.
    deplist = Array.new
    pkgver = nil
 
    blocks = find_block(database)
    blocks.each_with_index do |block, index|
        checkPackage = block[2].scan(/HPKGNAME=(.+$)/)
        checkPackage = checkPackage.join
        if packages.include?(checkPackage)
            i = blocks[index][0]
            endBlock = blocks[index][1]
            while i <= endBlock
                if database[i] != nil
                    if database[i].include? "DEPLIST="
                        newdeps = database[i].scan(/DEPLIST=(.+$)/)
                        newdeps = newdeps.join
                        newdeps = newdeps.split
                        deplist += newdeps
                    end
                end
            i += 1
            end
        end
        if deplist.empty? == false
            deplist.each do |dependency, pkgver|
                blocks.each_with_index do |block, index|
                    namecheck = block[2].scan(/HPKGNAME=(.+$)/)
                    namecheck = namecheck.join
                    if dependency == namecheck
                        i = block[0]
                        endBlock = block[1]
                        while i <= endBlock
                            if database[i] != nil
                                if database[i].include? "PKGVER="
                                    if not database[i].include? "HPKGVER="
                                        pkgver = database[i].scan(/PKGVER=(.+$)/)
                                        pkgver = pkgver.join
                                        if not is_installed(dependency, pkgver)
                                            if not packages.include?(dependency)
                                                packages.unshift(dependency)
                                                package_queue(packages)
                                            end
                                        end
                                    end
                                end
                            end
                        i += 1
                        end
                    end
                end
            end
        end
    end
end

def package_queue(packages)
    # Resolve the dependencies. Check each package to be installed's in the
    # database for the list of dependencies. For each dependency, check whether 
    # or not it is installed. If not, add it to the start of the list of 
    # packages to be installed. Each time a new package is added to the list, 
    # double check the list to ensure all missing dependencies are to be installed.
    packages.each do |packageName|
        # Open the control file and read the pertinent information.
        database = IO.readlines("/etc/hpm/pkginfo/hpmDatabase.info")

        queue_check(database, packageName, packages)
    end
end

def is_installed(packageName, pkgver)
    #Query the database to check if the package is already installed on the system.
    dbFile = File.open("/etc/hpm/pkdb/inpk.pkdb", "r")
    if checkFile(dbFile, "#{packageName}//#{pkgver}") == true
        dbFile.close
        return true
    else
        dbFile.close
        return false
    end
end

def log_installinfo(packageName, binfile, binpath, desktopentry)
    # Create a list of files and directories installed by the package.
    # eliminate the extra information, and write it to a file to be
    # called during the remove function and upgrade functions. 

    uninstallInfo = []
    baseUninstallInfo = `tar -tf /opt/hpm/tmp/#{packageName}.hpac`
    baseUninstallInfo = baseUninstallInfo.lines
    baseUninstallInfo.each do |entry|
        entry.chomp
        entry = entry.scan(/#{packageName}\/(.+$)/)
        entry = entry.join
        uninstallInfo.push(entry)
    end
    uninstallInfo.delete(binfile)
    i = 0
    endFile = uninstallInfo.length + 1
    confbool = 0
    while i <= endFile
        if not uninstallInfo[i] == nil
            if uninstallInfo[i].include? ".conscript"
                uninstallInfo.delete(uninstallInfo[i]) 
            end
        end
        if not uninstallInfo[i] == nil
            if uninstallInfo[i].include? ".desktop"
                uninstallInfo.delete(uninstallInfo[i]) 
            end
        end
        if not uninstallInfo[i] == nil
            if uninstallInfo[i].include? ".hpac"
                uninstallInfo.delete(uninstallInfo[i]) 
            end
        end
        if not uninstallInfo[i] == nil
            if uninstallInfo[i].include? ".conflist"
		        confbool = 1
                uninstallInfo.delete(uninstallInfo[i]) 
            end
	    end
        i += 1
    end

    if not desktopentry == nil
        uninstallDesktop = desktopentry.scan(/\/opt\/hpm\/tmp\/#{packageName}\/(.+$)/)
        uninstallDesktop = uninstallDesktop.join
    end
    uninstallInfo.delete("#{packageName}.control")

    uninstallInfo.push("usr/share/applications/#{uninstallDesktop}")
    uninstallInfo.push("etc/hpm/controls/#{packageName}.control")

    if not binfile == "" || binfile == "N/A"
        uninstallBinpath = binpath.reverse
        uninstallBinpath = uninstallBinpath.chop
        uninstallBinpath = uninstallBinpath.reverse
        uninstallBinfile = "#{uninstallBinpath}/#{binfile}"
        uninstallInfo.push(uninstallBinfile)
    end

    fileList = Array.new
    uFile = File.open("/etc/hpm/pkdb/uinfo/#{packageName}.uinfo", "w")
    uninstallInfo.each do |line|
        line = line.chomp
        if not line == "#{packageName}.desktop"
            uFile.puts line
        end
        if not line == nil
            dirCheck = line.length - 1
            if not dirCheck == line.rindex("/")
                if not line == "#{packageName}.desktop"
                    fileList.push(line)
                end
            end
        end
    end
    uFile.close

    md5List = Array.new
    fileList.each do |file|
        md5info = `md5sum /#{file}`
        md5info = md5info.scan(/(.+)\ .+$/)
        md5info = md5info.join
        md5info = file + " -- " +md5info
        md5List.push(md5info)
    end

    upgradeFile = File.open("/etc/hpm/pkdb/upinfo/#{packageName}.upinfo", "w")
    md5List.each do |line|
        upgradeFile.puts line
    end
    upgradeFile.close

    return confbool
end

def version_check(updateBlocks, installedPackageName, installedPackageVersion)
    # Check if the installed version is the same as the version available in 
    # the master repository database, if not, add the package to a list 
    # to be installed during the "upgrade" function.

    updateBlocks.each_index do |index|
        i = updateBlocks[index][0]
        endBlock = updateBlocks[index][1]
        checkPackageName = updateBlocks[index][2].scan(/HPKGNAME=(.+$)/)
        checkPackageName = checkPackageName.join
        if checkPackageName == installedPackageName
            while i <= endBlock
                if not $hpmDatabase[i] == nil
                    if $hpmDatabase[i].include? "PKGVER="
                        if not $hpmDatabase[i].include? "HPKGVER="
                            repoCheckVersion = $hpmDatabase[i].scan(/PKGVER=(.+$)/)
                            repoCheckVersion = repoCheckVersion.join
                            repoCheckVersion = repoCheckVersion.scan(/\d+/)
                            repoCheckVersion = repoCheckVersion.join
                            installedPackageVersion = installedPackageVersion.scan(/\d+/)  
                            installedPackageVersion = installedPackageVersion.join
                            if repoCheckVersion != installedPackageVersion
                                if not $updateDatabase.include?(installedPackageName)
                                    $updateDatabase.push(installedPackageName)
                                end
                            end
                        end
                    end
                end
                i += 1
            end
        end
    end
end

def database_check(hpmBlock, databaseData, hpmversioninfo, nameinfo)
    # Check the new repository's database versus the master list. If the new
    # repository has a version of the package greater than the version in
    # the master list, replace that block in the master database with the
    # block from the new list. 

    newBlocks = find_block(databaseData)
    newBlocks.each_index do |newBlockIndex|
        i = newBlocks[newBlockIndex][0]
        endBlock = newBlocks[newBlockIndex][1]
        while i <= endBlock
            if not databaseData[i] == nil
                if databaseData[i].include?("HPKGVER=")
                    checkVersion = hpmversioninfo.scan(/HPKGVER=(.+$)/)
                    checkVersion = checkVersion.join
                    hpmBlock.each_with_index do |block, hpmIndex|
                        if block[2] == nameinfo
                            n = hpmBlock[hpmIndex][0] 
                            hpmStartBlock = hpmBlock[hpmIndex][0] 
                            hpmEndBlock = hpmBlock[hpmIndex][1] 
                            while n <= hpmEndBlock
                                if not $hpmDatabase[n] == nil
                                    if $hpmDatabase[n].include?("HPKGVER=")
                                        hpmCheckVersion = $hpmDatabase[n].scan(/HPKGVER=(.+$)/)
                                        hpmCheckVersion = hpmCheckVersion.join
                                    end
                                end
                                n += 1
                            end
                            if checkVersion > hpmCheckVersion
                                $hpmDatabase.slice!(hpmStartBlock..hpmEndBlock)
                                $hpmDatabase += databaseData
                            end
                        end
                    end
                    databaseData.clear
                end
            end
        i += 1
        end
    end
end

def update()
    #              ######   THIS IS IN PROTOTYPE FORM     #########
    # Build  a master local database which contains packgae information
    # available for a "show" type command as well as information for
    # the dependency resolution of the install process.

    mirrors = []
    mirrorfile = File.open("/etc/hpm/mirrors/mirror.lst", "r")
    mirrorfile.each_line {|line| mirrors.push line.chomp }
    mirrorfile.close
   
    databaseData = []
    newDatabase = []
    nameinfo = nil
    mirrorinfo = nil
    hpmversioninfo = nil
    versioninfo = nil
    depinfo = nil
    hashinfo = nil
    summaryinfo = nil

    $hpmDatabase = [] 
    mirrors.each do |mirror|
        mirror.chomp
        puts `wget -q -c -O /etc/hpm/pkginfo/newDatabase.info #{mirror}/package_database/package_database.info`
        newDatabase = IO.readlines("/etc/hpm/pkginfo/newDatabase.info")
        newDatabase = newDatabase.compact
    
        newBlocks = find_block(newDatabase)
        newBlocks.each_index do |newBlockIndex|
            startBlock = newBlocks[newBlockIndex][0]
            endBlock = newBlocks[newBlockIndex][1]

            nameinfo = newBlocks[newBlockIndex][2]
            mirrorinfo = "MIRROR=" + mirror

            i = startBlock 
            while i <= endBlock
                if not newDatabase[i] == nil
                    if newDatabase[i].include? "HPKGVER="
                        hpmversioninfo = newDatabase[i]
                        hpmversioninfo = hpmversioninfo.chomp
                    end
                    if newDatabase[i].include? "PKGVER="
                        if not newDatabase[i].include? "HPKGVER="
                            versioninfo = newDatabase[i]
                            versioninfo = versioninfo.chomp
                        end
                    end
                    if newDatabase[i].include? "DEPLIST="
                        depinfo = newDatabase[i]
                        depinfo = depinfo.chomp
                    end
                    if newDatabase[i].include? "SHA512SUM="
                        hashinfo = newDatabase[i]
                        hashinfo = hashinfo.chomp
                    end
                    if newDatabase[i].include? "SUMMARY="
                        summaryinfo = newDatabase[i]
                        summaryinfo = summaryinfo.chomp
                    end
                end
                i = i + 1
            end

            databaseData = [nameinfo, hpmversioninfo, versioninfo, mirrorinfo,\
                    depinfo, hashinfo, summaryinfo, "\n"]

    
            # ok kids... here's where things get complicated.
            # check if the current database entry includes the package, if so, 
            # check if the new database entry's package is at a newer version.
            # If so, delete that entry and enter a new one, if not, do nothing. 
            # once the database is ready, push it out to file.

            if $hpmDatabase.empty?
                $hpmDatabase += databaseData
            else
                hpmBlocks = find_block($hpmDatabase)
                if not hpmBlocks == nil
                    if $hpmDatabase.include? nameinfo
                        database_check(hpmBlocks, databaseData, hpmversioninfo, nameinfo)
                    else
                        $hpmDatabase += databaseData
                    end
                end
            end
        end
        FileUtils.rm("/etc/hpm/pkginfo/newDatabase.info")
    end
    hpmDatabaseFile = File.open("/etc/hpm/pkginfo/hpmDatabase.info", "w")
    hpmDatabaseFile.puts  $hpmDatabase
    hpmDatabaseFile.close

    # Check if the current version is the same as the version available from the repo,
    # if not, add it to a file which can be called to in the upgrade function
    
    $updateDatabase = []

    pkdbFile = File.open("/etc/hpm/pkdb/inpk.pkdb", "r")
    pkdbFile.each_with_index do |line, pkdbIndex|
        line.chomp!
        installedPackageName = line.scan(/(.+)\/\//)
        installedPackageName = installedPackageName.join
        installedPackageVersion = line.scan(/.+\/\/(.+$)/)
        installedPackageVersion = installedPackageVersion.join
        updateBlocks = find_block($hpmDatabase)
        $hpmDatabase.each_index do |index|
            if $hpmDatabase[index].include? installedPackageName
                version_check(updateBlocks, installedPackageName, installedPackageVersion)
            end
        end
    end
    updateDatabaseFile = File.open("/etc/hpm/pkginfo/updateDatabase.info", "w")
    updateDatabaseFile.puts $updateDatabase
    updateDatabaseFile.close

end

def sourceinstall(source_link, direct_link, repo_fetch)
    build_location = nil
    if direct_link == nil && repo_fetch == nil
        build_location = ARGV[0]
    elsif direct_link != nil && repo_fetch == nil
        build_script = direct_link.scan(/^.+\/(.+$)/)
        build_script = build_script.join
        puts `wget -q -c -O /opt/hpm/build/tmp/#{build_script} #{direct_link}`
        build_location = "/opt/hpm/build/tmp/#{build_script}"
    end
    if source_link == nil
        source_link = ARGV[1]
    else
        source_file = source_link.scan(/^.+\/(.+$)/)
        source_file = source_file.join
        puts "source_file: #{source_file.inspect}"
        puts `wget -q -c -O /opt/hpm/build/tmp/#{source_file} #{source_link}`
    end
    puts "Running the buildscript..."
    Dir.chdir("/opt/hpm/build/tmp/")
    puts `chmod +x #{build_location}`
    puts `#{build_location}`
    packageName = build_script.scan(/(^.+)\..+$/)
    packageName = packageName.join
    conflist = nil
    if Dir.exists? "/opt/hpm/tmp/#{packageName}"
        FileUtils.rm_rf(Dir.glob("/opt/hpm/tmp/#{packageName}*"))
    end
    FileUtils.mv("/opt/hpm/build/tmp/#{packageName}.hpac", "/opt/hpm/tmp/")
    exthpac(packageName)
    install(packageName, conflist)
end

def handleconfig(packageName, file)
    puts "It looks like the author of #{packageName} has included a new" \
        " version of the configuration file located at:\n/#{file}"
    puts "\nWould you like to continue using your configuration, or the new one? (c/n)"
    STDOUT.flush
    decision = STDIN.gets.chomp
    if decision == "C" || decision == "c" 
        FileUtils.mv("/opt/hpm/tmp/#{packageName}/#{file}", \
            "/opt/hpm/tmp/#{packageName}/#{file}.new")
    elsif decision == "N" || decision == "n"
        FileUtils.mv("/#{file}", "/#{file}.old")
    end
end

def install(packageName, conflist)
    # Open the .control file # to obtain the  necessary information for the 
    # package, move the exectuable to the correct path, run the control 
    # script, and register the package # in the local database.

    # Open the control file and read the pertinent information.

    puts "Installing #{packageName}..."
    data = []        
    f = File.open("/opt/hpm/tmp/#{packageName}/#{packageName}.control", "r")
    f.each_line {|line| data.push line }
    f.close
    binfile = nil
    binpath = nil
    conscript = nil
    pkgver = nil
    conffile = nil
    data.each do |line|
        line.chomp
        if line.include? "BIN_FILE="
            binfile = line.scan(/BIN_FILE=(.+$)/)
            binfile = binfile.join
        elsif line.include? "BIN_PATH="
            binpath = line.scan(/BIN_PATH=(.+$)/)
            binpath = binpath.join
        elsif line.include? "CONSCRIPT="
            conscript = line.scan(/CONSCRIPT=(.+$)/)
            conscript = conscript.join
        elsif line.include? "PKGVER="
            pkgver = line.scan(/PKGVER=(.+$)/)
            pkgver = pkgver.join
        end
    end

    if not binfile == "N/A"
        desktopentry = "/opt/hpm/tmp/#{packageName}/#{packageName}.desktop"
    end

    # Move BIN_FILE to BIN_PATH from .control file.
    if not binfile == "N/A"
        puts "Moving: #{binfile} from /opt/hpm/tmp/#{packageName}/#{binfile} to #{binpath}"
        hpacmv(packageName, binfile, binpath)
    end

    # if it is an update, check for config files and ask if they should be
    # updated.
    if conflist != nil
        conflist.each do |file|
            file = file.scan(/\/(.+$)/)
            file = file.join
            if File.exists?("/opt/hpm/tmp/#{packageName}/#{file}")
                handleconfig(packageName, file)
            end 
        end
    end 


    # move the directories to their correct locations.
    directories = Array.new
    dirList = Array.new
    directories = `ls -pm /opt/hpm/tmp/#{packageName}`    
    directories = directories.split(/, /)
    directories[-1] = directories[-1].chomp!
    directories.each do |check|
        dirCheck = check.length - 1
        if dirCheck == check.rindex("/")
            dirList.push(check)
        end
    end
    dirList.each do |directory|
        puts `cp -HanT /opt/hpm/tmp/#{packageName}/#{directory} /#{directory}`
    end

    # Run the control script
    if conscript != nil
        puts "Running control script..."
        puts `chmod +x /opt/hpm/tmp/#{packageName}/#{conscript}`
        puts `/opt/hpm/tmp/#{packageName}/#{conscript}`
    end

    # Register package within the database
    puts "Registering packgages in database"
    open('/etc/hpm/pkdb/inpk.pkdb', 'a') { |database|
            database.puts "#{packageName}//#{pkgver}" }
           
    # Register packages within the database
    if not binfile == "N/A"
        FileUtils.mv(desktopentry, "/usr/share/applications/")
    end
    FileUtils.mv("/opt/hpm/tmp/#{packageName}/#{packageName}.control", "/etc/hpm/controls/")

    # And save information to uninstall with:
    confbool = log_installinfo(packageName, binfile, binpath, desktopentry)
    if confbool == 1 
    	FileUtils.cp("/opt/hpm/tmp/#{packageName}/#{packageName}.conflist", "/etc/hpm/conflist/")
    end

    # And make the program executable.
    if not binfile == "N/A" || binfile == ""	
        puts `chmod +x #{binpath}/#{binfile}`
    end
end

def removeinfo(packageName, bupdate)
    # Read the uninstall data for the package to be removed. Remove the
    # files which were installed, then check the directories in which they
    # were installed to. If thoso directories are empty, remove those too.

    uninstallInfo = []
    dirList = []
    fileList = []
    puts "packageName: #{packageName.inspect}"
    f = File.open("/etc/hpm/pkdb/uinfo/#{packageName}.uinfo", "r")
    f.each_line {|line| uninstallInfo.push line }
    f.close
    if bupdate == 1
        return uninstallInfo
    else
        uninstallInfo.each do |entry|
            entry.chop!
            dirCheck = entry.length - 1
            if dirCheck == entry.rindex("/")
                dirList.push(entry)
            else
                fileList.push(entry)
            end
        end
    
        remove(packageName, dirList, fileList)
    end
end

def remove(packageName, dirList, fileList)

    # Delete all the files
    fileList.each do |file|
        file = "/#{file}"
        puts "Removing: #{file}"
        if File.exists?(file)
            FileUtils.rm(file)
        end
    end

    # Delete all of the now empty directories
    dirList.each do |directory|
        if Dir["/\/#{directory}/*"].empty? then
            directory = "/#{directory}"
            puts "Removing: #{directory}"
            FileUtils.rmdir(directory)
        end
    end
    
    # Delete the uinfo file and database entry
    FileUtils.rm("/etc/hpm/pkdb/uinfo/#{packageName}.uinfo")
    dbFile = File.open("/etc/hpm/pkdb/inpk.pkdb", "r")
    newDatabase = dbFile.readlines
    dbFile.close
    newDatabase.each do |line|
        if line.include? packageName
            newDatabase.delete(line)
        end
    end
    dbFile = File.open("/etc/hpm/pkdb/inpk.pkdb", "w")
    newDatabase.each do |line|
        dbFile.puts line
    end
    dbFile.close
     
end

def upgrade()

    packages = []
    upgradeFile = File.open("/etc/hpm/pkginfo/updateDatabase.info", "r")
    upgradeFile.each_line {|line| packages.push line }
    upgradeFile.close
    totalPackages = packages.length

    packages.each_with_index do |packageName, index|
        count = index + 1
        packageName = packageName.chomp
        uninstallInfo = []
        dirList = []
        fileList = []
        uninstallInfo = removeinfo(packageName, 1)
        uninstallInfo.each do |entry|
            entry.chop!
            dirCheck = entry.length - 1
            if dirCheck == entry.rindex("/")
                dirList.push(entry)
            else
                fileList.push(entry)
            end
        end

        if File.exists?("/etc/hpm/conflist/#{packageName}.conflist")
            configInfo = []
            configFile = File.open("/etc/hpm/conflist/#{packageName}.conflist")
            configFile.each_line {|line| configInfo.push line }
            configFile.close

            fileList.each do |file|
                configInfo.each do |configData|
                    configData = configData.chomp!
                    if configData == "/#{file}"
                        fileList.delete(file)
                    end
                end
            end
        end
    
        bupdate = 1
        gethpac(packageName, count, totalPackages)
        remove(packageName, dirList, fileList)
        exthpac(packageName)
        install(packageName, configInfo)
    end
end

def repoinstall(packages, totalPackages, bupdate)
    # Install a package from a mirror. Check for connectivity to the
    # mirror, if so, download the package, extract it. Install package.

    # mirror = # hmmm.
    
    # CHECK MIRROR STATUS ..... somehow

    # Get the required packages and extract them, then install them.
    
    databaseFile = File.open("/etc/hpm/pkginfo/hpmDatabase.info", "r")
    database = databaseFile.readlines
    databaseFile.close
    blocks = find_block(database)
    pkgver = nil

    packages.each_with_index do |packageName, index|
        blocks.each do |block|
            if block[2].include? packageName
                i = block[0]
                endBlock = block[1]
                while i <= endBlock
                    if not database[i] == nil
                        if database[i].include?("PKGVER=")
                            if not database[i].include?("HPKGVER=")
                                pkgver = database[i].scan(/PKGVER=(.+$)/)
                                pkgver = pkgver.join
                            end
                        end
                    end
                i += 1
                end
            end
        end
        if is_installed(packageName, pkgver)
            puts "#{packageName} is already at the newest version."
            packages.delete(packageName)
        else
            count = index + 1
            gethpac(packageName, count, totalPackages)
        end
    end

    if bupdate == 0
        conflist = nil
        packages.each do |packageName|
            exthpac(packageName)
        end

        packages.each do |packageName|
            install(packageName, conflist)
        end
    end
end

def localinstall(packages)
    # Install a package from a local sourc. Extract it. Clean Input, and
    # install the package. 

    packages.each do |packageName|
        puts "Copying #{packageName} to /opt/hpm/tmp/..."
        FileUtils.cp("#{packageName}", "/opt/hpm/tmp/")
    end

    packages.each do |packageName|
        if packageName.include? ".hpac"
            packageName = packageName.chomp('.hpac')
        end
        puts "Extracting #{packageName}..."
        exthpac(packageName)
    end

    packages.each do |packageName|
        if packageName.include? ".hpac"
            packageName = packageName.chomp('.hpac')
        end
            conflist = nil
            install(packageName, conflist)
    end
end

def makepkg(package_folder, output_file)
    move = true
    Dir.chdir(package_folder)
    package_folder = Dir.pwd
    Dir.chdir("../")
    if output_file == nil 
        move = false
        output_file = "#{package_folder}.hpac"
    end
    package_folder = package_folder.scan(/^.+\/(.+$)/)
    package_folder = package_folder.join
    dirCheck = output_file.length - 1
    if Dir.exists?(output_file)
        if dirCheck == output_file.rindex("/")
            output_file = "#{output_file}#{package_folder}.hpac" 
        else    
            output_file = "#{output_file}/#{package_folder}.hpac" 
        end
    end
    output_location = output_file.scan(/(^.+\/).+$/)
    output_location = output_location.join
    if output_lotation = package_folder
        move = false
    end
    
    output_file = output_file.scan(/^.+\/(.+$)/)
    output_file = output_file.join
    package_folder = "#{package_folder}/*"
    puts `tar -cjf #{output_file} #{package_folder}`
    if move == true
        FileUtils.mv(output_file, output_location)
    end
end

# Get input from the user by means of arguments passed along with the program.
# The first argument following the command is considered the action in the
# program. All subsequent arguments are considered to be packages.
arg_delete_list = Array.new
output_file = nil
source_link = nil
get_build = nil
repo_fetch = nil
ARGV
action = ARGV.shift
ARGV.each_with_index do |argument, index|
    if  argument == "-o" || argument == "--output-file"
        next_index = index + 1
        output_file = ARGV[next_index]
        arg_delete_list.push(argument)
        arg_delete_list.push(output_file)
    elsif  argument == "-s" || argument == "--source-link"
        next_index = index + 1
        source_link = ARGV[next_index]
        arg_delete_list.push(argument)
        arg_delete_list.push(source_link)
    elsif  argument == "-d" || argument == "--direct-link"
        next_index = index + 1
        get_build = ARGV[next_index]
        arg_delete_list.push(argument)
        arg_delete_list.push(get_build)
    elsif  argument == "-r" || argument == "--repo-fetch"
        next_index = index + 1
        repo_fetch = ARGV[next_index]
        arg_delete_list.push(argument)
        arg_delete_list.push(repo_fetch)
    end 
end
arg_delete_list.each do |delete_item|
    ARGV.delete(delete_item)
end

packages = ARGV

# Decide which course of action to take
case action
    when "install"
        package_queue(packages)
        packageDisplay = packages.join(" ") 
        puts "Packages to be installed:\n\n#{packageDisplay}\n"
        puts "\nProceed with installation? (y/n)"
        STDOUT.flush
        decision = STDIN.gets.chomp
        if decision == "Y" || decision == "y" || decision == "yes"
            totalPackages = packages.length
            bupdate = 0
            repoinstall(packages, totalPackages, bupdate)
        else
            puts "Aborting Installation"
        end
    when "remove"; packages.each {|package| removeinfo(package, 0)}
    when "source-install"
        sourceinstall(source_link, get_build, repo_fetch)
    when "local-install"
        package_queue(packages)
        packageDisplay = packages.join(" ") 
        puts "Packages to be installed:\n\n#{packageDisplay}\n"
        puts "\nProceed with installation? (y/n)"
        STDOUT.flush
        decision = STDIN.gets.chomp
        if decision == "Y" || decision == "y" || decision == "yes"
            localinstall(packages)
        else
            puts "Aborting Installation"
        end
    when "clean"; clean
    when "update"; update
    when "upgrade"; upgrade
    when "makepkg"
        packages.each {|package|makepkg(package, output_file)}
    else helpPage
end
