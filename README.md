# Tools to find duplicate and/or unmatched items in Jellyfin Libraries
Hello world.

A quick a dirty repo for tools to find duplicate and/or unmatched items in Jellyfin Libraries.

The first tool is a bash script.
1. Download the script
2. Find your Jellyfin URL
3. Get an API key from the admin dashboard of Jellyfin
4. Make sure you have CURL + JQ installed (typically comes with Linux/MacOS but not sure on windows)
5. Add the URLs and API key to the script
6. Run the script using sh find_unmatched_and_duplicates_jellyfin_items.sh
     (or chmod it so its executable)

It will ask you which Jellyfin Library to search, whether you want to look for unmatched or duplicate items (or both), then output either to the screen or to a CSV file...


Enjoy...
