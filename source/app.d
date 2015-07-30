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
import std.exception;

string destDirRoot;
bool infoMode;
bool copyFile;
bool testMode;
string dirFormat="yyyy/yyyymm";

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
	auto f = enforce(FreeImage_LoadU(FIF_JPEG, u), "not a JPEG image");
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

void OutputMetadataByCategory(FIBITMAP* f, FREE_IMAGE_MDMODEL model, string modelName)
{
	writefln("%s------------------------------------------", modelName);
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
				case FIDT_BYTE:
					kv = to!string(*cast(const(ubyte)*)kvv);
					break;
				case FIDT_ASCII:
				case FIDT_UNDEFINED:
					kv = to!string(cast(const(char)*)kvv);
					break;
				case FIDT_SHORT:
					kv = to!string(*cast(const(ushort)*)kvv);
					break;
				case FIDT_LONG:
					kv = to!string(*cast(const(uint)*)kvv);
					break;
				case FIDT_RATIONAL:
					auto ki = cast(const(uint)*)kvv;
					kv = to!string(ki[0]) ~ "/" ~ to!string(ki[1]);
					break;
				case FIDT_SBYTE:
					kv = to!string(*cast(const(byte)*)kvv);
					break;
				case FIDT_SSHORT:
					kv = to!string(*cast(const(short)*)kvv);
					break;
				case FIDT_SLONG:
				case FIDT_IFD:
					kv = to!string(*cast(const(int)*)kvv);
					break;
				case FIDT_SRATIONAL:
					auto ki = cast(const(int)*)kvv;
					kv = to!string(ki[0]) ~ "/" ~ to!string(ki[1]);
					break;
				case FIDT_FLOAT:
					kv = to!string(*cast(const(float)*)kvv);
					break;
				case FIDT_DOUBLE:
					kv = to!string(*cast(const(double)*)kvv);
					break;
				case FIDT_PALETTE:
					kv = to!string(*cast(const(uint)*)kvv);
					break;

				default:
					break;
			}
			writefln("  %s: %s", kn, kv);
		} while(FreeImage_FindNextMetadata(handle, &tag)); 
		FreeImage_FindCloseMetadata(handle); 
	} 	
}

void OutputFileInfo(string path)
{
	auto u = path.toUTF16z();
	FIBITMAP* f = enforce(FreeImage_LoadU(FIF_JPEG, u), "not a JPEG image");
	scope(exit) FreeImage_Unload(f);

	OutputMetadataByCategory(f, FIMD_COMMENTS, "Comments");
	OutputMetadataByCategory(f, FIMD_EXIF_MAIN, "EXIF.main");
	OutputMetadataByCategory(f, FIMD_EXIF_EXIF, "EXIF.exif");
	OutputMetadataByCategory(f, FIMD_EXIF_GPS, "EXIF.GPS");
	OutputMetadataByCategory(f, FIMD_EXIF_MAKERNOTE, "EXIF.maker note");
	OutputMetadataByCategory(f, FIMD_EXIF_INTEROP, "EXIF.inter operation");
	OutputMetadataByCategory(f, FIMD_EXIF_RAW, "EXIF.raw");
	OutputMetadataByCategory(f, FIMD_IPTC, "IPTC");
	OutputMetadataByCategory(f, FIMD_XMP, "XMP");
	OutputMetadataByCategory(f, FIMD_GEOTIFF, "GEOTIFF");
	OutputMetadataByCategory(f, FIMD_ANIMATION, "Animation");
	OutputMetadataByCategory(f, FIMD_CUSTOM, "Custom");
}

void ProcessSingleFile(string path)
{
	writeln(path);

	if (infoMode)
	{
		OutputFileInfo(path);
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
		"test", "Test mode, do not perform file operation, just print", &testMode
		);
	if (helpInformation.helpWanted)
	{
		defaultGetoptPrinter("Orgnize photos according to their taken date.", helpInformation.options);
		return;
	}

	if (destDirRoot == "" && !infoMode)
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
