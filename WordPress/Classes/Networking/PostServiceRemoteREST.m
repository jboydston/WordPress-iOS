#import "PostServiceRemoteREST.h"
#import "WordPressComApi.h"
#import "Blog.h"
#import "RemotePost.h"
#import "RemoteCategory.h"
#import "NSDate+WordPressJSON.h"

@interface PostServiceRemoteREST ()

@property (nonatomic, strong) WordPressComApi *api;

@end

@implementation PostServiceRemoteREST

- (id)initWithApi:(WordPressComApi *)api {
    self = [super init];
    if (self) {
        _api = api;
    }
    return self;
}

- (void)getPostsForBlog:(Blog *)blog
                success:(void (^)(NSArray *))success
                failure:(void (^)(NSError *))failure {
    [self getPostsForBlog:blog options:nil success:success failure:failure];
}

- (void)getPostsForBlog:(Blog *)blog
                options:(NSDictionary *)options
                success:(void (^)(NSArray *))success
                failure:(void (^)(NSError *))failure {
    NSString *path = [NSString stringWithFormat:@"sites/%@/posts", blog.dotComID];
    NSDictionary *parameters = @{
                                 @"status": @"any",
                                 @"context": @"edit",
                                 @"number": @40,
                                 };
    if (options) {
        NSMutableDictionary *mutableParameters = [parameters mutableCopy];
        [mutableParameters addEntriesFromDictionary:options];
        parameters = [NSDictionary dictionaryWithDictionary:mutableParameters];
    }
    [self.api GET:path
       parameters:parameters
          success:^(AFHTTPRequestOperation *operation, id responseObject) {
              if (success) {
                  success([self remotePostsFromJSONArray:responseObject[@"posts"]]);
              }
          } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
              if (failure) {
                  failure(error);
              }
          }];
}

- (void)createPost:(RemotePost *)post
           forBlog:(Blog *)blog
           success:(void (^)(RemotePost *))success
           failure:(void (^)(NSError *))failure
{
    NSString *path = [NSString stringWithFormat:@"sites/%@/posts/new?context=edit", blog.dotComID];
    NSDictionary *parameters = [self parametersWithRemotePost:post];

    [self.api POST:path
        parameters:parameters
           success:^(AFHTTPRequestOperation *operation, id responseObject) {
               RemotePost *post = [self remotePostFromJSONDictionary:responseObject];
               if (success) {
                   success(post);
               }
           } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
               if (failure) {
                   failure(error);
               }
           }];
}

- (void)updatePost:(RemotePost *)post
           forBlog:(Blog *)blog
           success:(void (^)(RemotePost *))success
           failure:(void (^)(NSError *))failure
{
    NSString *path = [NSString stringWithFormat:@"sites/%@/posts/%@?context=edit", blog.dotComID, post.postID];
    NSDictionary *parameters = [self parametersWithRemotePost:post];

    [self.api POST:path
        parameters:parameters
           success:^(AFHTTPRequestOperation *operation, id responseObject) {
               RemotePost *post = [self remotePostFromJSONDictionary:responseObject];
               if (success) {
                   success(post);
               }
           } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
               if (failure) {
                   failure(error);
               }
           }];
}

#pragma mark - Private methods

- (NSArray *)remotePostsFromJSONArray:(NSArray *)jsonPosts {
    NSMutableArray *posts = [NSMutableArray arrayWithCapacity:jsonPosts.count];
    for (NSDictionary *jsonPost in jsonPosts) {
        [posts addObject:[self remotePostFromJSONDictionary:jsonPost]];
    }
    return [NSArray arrayWithArray:posts];
}

- (RemotePost *)remotePostFromJSONDictionary:(NSDictionary *)jsonPost {
    RemotePost *post = [RemotePost new];
    post.postID = jsonPost[@"ID"];
    post.siteID = jsonPost[@"siteID"];
    post.authorAvatarURL = jsonPost[@"author"][@"URL"];
    post.authorDisplayName = jsonPost[@"author"][@"name"];
    post.authorEmail = [jsonPost[@"author"] stringForKey:@"email"];
    post.authorURL = jsonPost[@"author"][@"URL"];
    post.date = [NSDate dateWithWordPressComJSONString:jsonPost[@"date"]];
    // FIXME: the API returns invalid dates for drafts
    // Use the last modified date until this is resolved, otherwise drafts get
    // pushed to the end of the posts list
    if (post.date == nil) {
        post.date = [NSDate dateWithWordPressComJSONString:jsonPost[@"modified"]];
    }
    post.title = jsonPost[@"title"];
    post.URL = [NSURL URLWithString:jsonPost[@"URL"]];
    post.shortURL = [NSURL URLWithString:jsonPost[@"short_URL"]];
    post.content = jsonPost[@"content"];
    post.excerpt = jsonPost[@"excerpt"];
    post.slug = jsonPost[@"slug"];
    post.status = [self statusWithRemoteStatus:jsonPost[@"status"]];
    post.password = jsonPost[@"password"];
    if ([post.password isEmpty]) {
        post.password = nil;
    }
    post.parentID = jsonPost[@"parent"];
    // post_thumbnail can be null, which will transform to NSNull, so we need to add the extra check
    NSDictionary *postThumbnail = [jsonPost dictionaryForKey:@"post_thumbnail"];
    post.postThumbnailID = [postThumbnail numberForKey:@"ID"];
    post.type = jsonPost[@"type"];
    post.format = jsonPost[@"format"];

    // FIXME: remove conversion once API is fixed
    // metadata should always be an array but it's returning false when there are no custom fields
    post.metadata = [jsonPost arrayForKey:@"metadata"];
    // post.metadata = jsonPost[@"metadata"];

    NSDictionary *categories = jsonPost[@"categories"];
    if (categories) {
        post.categories = [self remoteCategoriesFromJSONArray:[categories allValues]];
    }
    post.tags = [self tagNamesFromJSONDictionary:jsonPost[@"tags"]];

    return post;
}

- (NSDictionary *)parametersWithRemotePost:(RemotePost *)post
{
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"title"] = post.title;
    parameters[@"content"] = post.content;
    parameters[@"status"] = post.status;
    parameters[@"password"] = post.password ? post.password : @"";
    parameters[@"type"] = post.type;

    if (post.date) {
        parameters[@"date"] = post.date;
    }
    if (post.excerpt) {
        parameters[@"excerpt"] = post.excerpt;
    }
    if (post.slug) {
        parameters[@"slug"] = post.slug;
    }
    if (post.parentID) {
        parameters[@"parent"] = post.parentID;
    }

    parameters[@"categories"] = [post.categories valueForKey:@"categoryID"];
    parameters[@"tags"] = post.tags ? post.tags : @[];
    parameters[@"format"] = post.format ? post.format : @"standard";
    parameters[@"featured_image"] = post.postThumbnailID ? [post.postThumbnailID stringValue] : @"";
    // TODO: metadata
    // Test what happens for nil and not present values
    return [NSDictionary dictionaryWithDictionary:parameters];
}

- (NSString *)statusWithRemoteStatus:(NSString *)remoteStatus {
    NSString *status = remoteStatus;
    if ([status isEqualToString:@"future"]) {
        status = @"publish";
    }
    return status;
}

- (NSArray *)remoteCategoriesFromJSONArray:(NSArray *)jsonCategories {
    NSMutableArray *categories = [NSMutableArray arrayWithCapacity:jsonCategories.count];
    for (NSDictionary *jsonCategory in jsonCategories) {
        [categories addObject:[self remoteCategoryFromJSONDictionary:jsonCategory]];
    }
    return [NSArray arrayWithArray:categories];
}

- (RemoteCategory *)remoteCategoryFromJSONDictionary:(NSDictionary *)jsonCategory {
    RemoteCategory *category = [RemoteCategory new];
    category.categoryID = jsonCategory[@"ID"];
    category.name = jsonCategory[@"name"];
    category.parentID = jsonCategory[@"parent"];

    return category;
}

- (NSArray *)tagNamesFromJSONDictionary:(NSDictionary *)jsonTags {
    return [jsonTags allKeys];
}

@end