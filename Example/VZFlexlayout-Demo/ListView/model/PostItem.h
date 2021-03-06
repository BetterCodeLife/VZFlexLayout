//
//  PostItem.h
//  VZFlexlayout-Demo
//
//  Created by Tao Xu on 9/17/18.
//  Copyright © 2018 Vizlab. All rights reserved.
//

#import "VZListItem.h"
@class PostItemStore;
@interface PostItem : VZListItem<VZFNodeProvider>

@property(nonatomic,strong) NSNumber* userId;
@property(nonatomic,strong) NSString* title;
@property(nonatomic,strong) NSString* body;
@property(nonatomic,strong) PostItemStore* store;
@property(nonatomic,assign) float contentWidth;
@property(nonatomic,assign) float contentHeight;
@property(nonatomic,readonly,strong) UIView* attachedView;


- (void)updateModelWithConstrainedSize:(CGSize)sz context:(id)context;
- (void)updateState;
- (void)attachToView:(UIView *)view;
- (void)detachFromView;

@end
