import std.stdio;
import std.getopt;
import derelict.freeimage.freeimage;
import std.conv;
import std.utf;
import std.file;
import std.path;
import std.datetime;
import std.format;
import std.string;

string destDirRoot;
bool infoMode;
bool copyFile;
bool testMode;
string dirFormat="yyyy/yyyymm";
string extFilter="jpg";

bool ContentEqual(string path1, string path2)
{
	return
		isFile(path1) && 
		isFile(path2) &&
		getSize(path1) == getSize(path2) &&
		read(path1) == read(path2);
}

unittest
{
	auto f1 = File("deleteme.1", "w");
	f1.write("hello");
	f1.close();
	auto f2 = File("deleteme.2", "w");
	f2.write("hello");
	f2.close();
	auto f3 = File("deleteme.3", "w");
	f3.write("hell0");
	f3.close();
	assert(ContentEqual("deleteme.1", "deleteme.2"));
	assert(!ContentEqual("deleteme.1", "deleteme.3"));
	std.file.remove("deleteme.1");
	std.file.remove("deleteme.2");
	std.file.remove("deleteme.3");
}

bool GetPhotoTakenTime(string path, DateTime* dt)
{	
	FITAG* tag;
	auto u = path.toUTF16z();
	auto f = FreeImage_LoadU(FIF_JPEG, u);
	scope(exit) FreeImage_Unload(f);

	if (!FreeImage_GetMetadata(FIMD_EXIF_EXIF, f, "DateTimeOriginal", &tag))
	{
		if (!FreeImage_GetMetadata(FIMD_EXIF_MAIN, f, "DateTimeOriginal", &tag))
		{
			if (!FreeImage_GetMetadata(FIMD_EXIF_MAIN, f, "DateTime", &tag))
			{
				if (!FreeImage_GetMetadata(FIMD_EXIF_EXIF, f, "DateTime", &tag))
					return false;
			}
		}
	}

	const(void)* v = FreeImage_GetTagValue(tag);
	const(char)* vc = cast(const(char)*)v;
	string vs = to!string(vc);
	if (vs.length < 19)
	{
		return false;
	}

	dt.year = to!int(vs[0..4]);
	dt.month = to!Month(to!int(vs[5..7]));
	dt.day = to!int(vs[8..10]);
	dt.hour = to!int(vs[11..13]);
	dt.minute = to!int(vs[14..16]);
	dt.second = to!int(vs[17..19]);
	return true;
}

void OutputMetadataByCategory(FIBITMAP* f, FREE_IMAGE_MDMODEL model)
{
	FITAG* tag;
	auto handle = FreeImage_FindFirstMetadata(model, f, &tag); 
	if(handle) { 
		do { 
			string kn = to!string(FreeImage_GetTagKey(tag));
			string kv;
			auto kt = FreeImage_GetTagType(tag);
			auto kvv = FreeImage_GetTagValue(tag);
			switch (kt)
			{
				case FIDT_ASCII:
					const(char)* kc = cast(const(char)*)kvv;
					kv = to!string(kc);
					break;
				default:
					break;
			}
			writefln("  %s:%s", kn, kv);
		} while(FreeImage_FindNextMetadata(handle, &tag)); 
		FreeImage_FindCloseMetadata(handle); 
	} 	
}

void OutputFileInfo(string path)
{
	auto u = path.toUTF16z();
	FIBITMAP* f = FreeImage_LoadU(FIF_JPEG, u);
	scope(exit) FreeImage_Unload(f);

	for (int x = 0; x < 12; x++)
	{
		writeln("  ", x, "------------------------------------------");
		OutputMetadataByCategory(f, to!FREE_IMAGE_MDMODEL(x));
	}

}

void ProcessSingleFile(string path)
{
	writeln(path);

	if (infoMode)
	{
		OutputFileInfo(path);
		return;
	}

	if (extension(path).toLower() != "."~extFilter.toLower())
	{
		return;
	}

	DateTime dt;
	string subdir = "unsort";
	if (GetPhotoTakenTime(path, &dt))
	{
		string year = to!string(dt.year);
		string month = format("%02d", to!int(dt.month));
		string day = format("%02d", dt.day);
		subdir = dirFormat.replace("yyyy", year).replace("mm", month).replace("dd", day);
	}

	string destDir = buildNormalizedPath(destDirRoot, subdir);
	string destPath = buildPath(destDir, baseName(path));

	// if 'destPath' already exists, we must find a new name
	if (exists(destPath))
	{
		if (ContentEqual(path, destPath))
			return;

		string base = baseName(stripExtension(path));
		string ext = extension(path);
		for (int x = 2; ; x++)
		{
			destPath = buildPath(destDir, format("%s %d%s", base, x, ext));
			if (!exists(destPath))
			{
				break;
			}
		}
	}

	if (!testMode)
	{
		mkdirRecurse(destDir);
		if (copyFile)
		{
			copy(path, destPath);
		}
		else
		{
			rename(path, destPath);
		}
	}

	writeln("-> ", destPath);
}

void main(string[] argv)
{
	auto helpInformation = getopt(
		argv, 
		"dest|D", "Set destination path", &destDirRoot,
		"info", "Info mode: only output file information", &infoMode,
		"dirformat|f", "Directory format, default to 'yyyy/yyyymm'", &dirFormat,
		"copy", "Copy file instread of move", &copyFile,
		"ext", "File extension", &extFilter,
		"test", "Test mode, do not perform file operation, just print", &testMode
		);
	if (helpInformation.helpWanted)
	{
		defaultGetoptPrinter("Orgnize photos according to their taken date.", helpInformation.options);
		return;
	}

	if (destDirRoot == "")
	{
		writeln("Please give destination path");
		return;
	}

	DerelictFI.load();
	FreeImage_Initialise();
	scope(exit) FreeImage_DeInitialise();

	foreach (string path; argv[1..$])
	{
		try
		{
			if (isFile(path))
			{
				ProcessSingleFile(path);
			}
			else
			{
				auto files = dirEntries(path, SpanMode.depth);
				foreach (string f ; files)
				{
					if (isFile(f))
					{
						ProcessSingleFile(f);
					}
				}
			}
		}
		catch (Exception e)
		{
			writeln("error: ", e.msg);
		}
	}
}
