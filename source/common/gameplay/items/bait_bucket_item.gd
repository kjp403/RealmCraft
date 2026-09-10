class_name BaitBucketItem
extends AnglerToolItem
## The Bottomless Bait Bucket. Right-click Fill sweeps every loose Fish Bait stack
## out of the bags and into the bucket in one server call — no panel, because there
## is nothing to choose.
##
## THE BUCKET HOLDS NO STATE OF ITS OWN. The charge lives on
## [member PlayerResource.stored_bait] and is only ever touched through
## [BaitBucket]. An @export here would be shared by every player on the server,
## because item resources are loaded once and handed out by reference — see the
## note on BaitBucket for the full reasoning and for the second, independent way
## per-slot storage loses it.


func action_label() -> String:
	return "Fill"


func server_request() -> StringName:
	return &"bait.fill"
