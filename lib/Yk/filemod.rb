require 'Yk/auto_pstore'

	class FileMod
		AutoPstore.fileMod ||= {}
		@@fList = {}
		def FileMod.updated? (fName)
			m = AutoPstore.fileMod[fName]
			AutoPstore.setFinalizer(:fileMod, fName) do |obj|
				if fName.exist?
					obj[fName] = fName.mtime
				else
					obj.delete fName
				end
			end
			m || m < fName.mtime
		end
	end


