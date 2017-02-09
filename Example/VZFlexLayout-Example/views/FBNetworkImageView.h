//
//  FBNetworkImageView.h
//  VZFlexLayout
//
//  Created by moxin on 16/5/1.
//  Copyright © 2016年 Vizlab. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "VZFNetworkImageDownloadProtocol.h"
#import "VZFImageNodeBackingView.h"

@interface FBNetworkImageView : VZFImageNodeBackingView <VZFNetworkImageDownloadProtocol>

@end