//
//  VZFNode.m
//  VZFlexLayout
//
//  Created by moxin on 16/1/26.
//  Copyright © 2016年 Vizlab. All rights reserved.
//

#import "VZFNode.h"
#import "VZFUtils.h"
#import "VZFMacros.h"
#import "VZFlexNode.h"
#import "VZFNodeLayout.h"
#import "VZFNodeInternal.h"
#import "VZFNodeLifeCycle.h"
#import "VZFlexNode+VZFNode.h"
#import "VZFNodeMountContext.h"
#import "VZFNodeViewManager.h"
#import "VZFNodeMountContext.h"
#import "VZFNodeSpecs.h"
#import "VZFNodeViewClass.h"
#import "UIView+VZAttributes.h"
#import "VZFNodeBackingViewInterface.h"
#import "VZFRenderer.h"
#import "VZFRasterizeNodeTool.h"
#import "VZFBackingViewProtocol.h"

struct VZFNodeMountedInfo{
  
    __weak VZFNode* parentNode;
    __weak UIView* mountedView;
    __weak VZFRenderer* mountedRenderer;
    
    struct {
        __weak UIView* v;
        __weak VZFRenderer* r;
        CGRect frame;
    } mountedContext;
};


using namespace VZ;
using namespace VZ::UIKit;

@implementation VZFNode
{
    
    VZFNodeLifeCycleState _lifeCycleState;
    std::unique_ptr<VZFNodeMountedInfo> _mountedInfo;
}


+ (instancetype)newWithView:(const ViewClass &)viewclass NodeSpecs:(const NodeSpecs &)specs{

    return [[self alloc] initWithView: viewclass Specs:specs];
}

+ (instancetype)new
{
    return [self newWithView:[UIView class] NodeSpecs:{}];
}

- (instancetype)initWithView:(const ViewClass& )viewclass Specs:(const NodeSpecs& )specs{
    self = [super init];
    if (self) {
        
        _specs          = specs;
        _viewClass      = viewclass;
        _flexNode       = [VZFlexNode flexNodeWithSpecs:specs];
        _flexNode.name  = [NSString stringWithUTF8String:specs.identifier.c_str()];
        _flexNode.fNode = self;

    }
    return self;
}

- (instancetype)init
{
    VZ_NOT_DESIGNATED_INITIALIZER();
}

- (void)dealloc{
    
//    VZF_LOG_DEALLOC();
    
    _flexNode.fNode = nil;
    _mountedInfo.reset();
    _mountedInfo = nullptr;
}

- (UIView* )mountedView{

    if (_mountedInfo) {
        return _mountedInfo -> mountedView;
    }
    else{
        return nil;
    }
}

- (NodeLayout)computeLayoutThatFits:(CGSize)sz{
    
    [_flexNode layout:sz];
    NodeLayout layout = { self,
                             _flexNode.resultFrame.size,
                             _flexNode.resultFrame.origin,
                             _flexNode.resultMargin};
    return [self nodeDidLayout];
}

- (BOOL)shouldMemoizeLayout{
    
    return NO;
}

- (NodeLayout)nodeDidLayout{
    NodeLayout layout{
        self,
        self.flexNode.resultFrame.size,
        self.flexNode.resultFrame.origin,
        self.flexNode.resultMargin,
        {}
    };
    
//    VZFNSLog(@"[%@]-->nodeDidLayout:%@",self.class, NSStringFromCGSize(layout.size));
    return layout;
}


- (NSString *)description {
    
    NSString* className = NSStringFromClass([self class]);
    return [[NSString alloc] initWithFormat:@"Class:{%@} \nLayout:{%@\n}",className,self.flexNode.description];
}

- (VZFNode* )superNode{
    return _mountedInfo -> parentNode;
}

- (VZFNode* )rootNode{
    
    VZFNode* rootNode = self;
    while (rootNode.superNode) {
        rootNode = rootNode.superNode;
    }
    return rootNode;
}

- (UIView* )rootView
{
    VZFNode* rootNode = [self rootNode];
    if (rootNode) {
        return rootNode -> _mountedInfo -> mountedView?:
        _mountedInfo->mountedContext.v;
    }
    else{
        return nil;
    }
}

-(VZ::UIKit::MountResult)renderInContext:(const VZ::UIKit::MountContext &)context Size:(CGSize) size ParentNode:(VZFNode* )parentNode
{
    
    //VZF_LOG_THREAD(@"mount");
    
    if (_mountedInfo == nullptr) {
        _mountedInfo.reset( new VZFNodeMountedInfo() );
    }
    
    _mountedInfo -> parentNode =  parentNode;
    
    
    //If renderer is nil, it means the node can't be rasterized
    //@discussion reuse?
    VZFRenderer *renderer = [VZFRasterizeNodeTool getRenderer4RasterizedNode:self size:size];
    VZFRenderer *parentRenderer = nil;
    
    if (parentNode != nil && parentNode -> _mountedInfo != nullptr) {
        parentRenderer = parentNode -> _mountedInfo -> mountedRenderer;
    }

    if (renderer && parentRenderer) {
        //当自己能被光栅化，且父节点也被光栅化的，renderer添加到父节点上
        
        //to rasterize
        //不是当前的backingview
        if (renderer != _mountedInfo -> mountedRenderer) {
            //释放当前mountedView绑定的node
            [renderer.node unmount];
            renderer.node = self;
            _mountedInfo -> mountedRenderer = renderer;
            //[self didAquireBackingView];
        }
        else{
            VZFAssert(renderer.node == self, @"");
        }
        
        //计算公式:
        //position.x = frame.origin.x + anchorPoint.x * bounds.size.width；
        //position.y = frame.origin.y + anchorPoint.y * bounds.size.height；
        /*       const CGPoint anchorPoint = view.layer.anchorPoint;
         view.center = context.position + CGPoint({anchorPoint.x * size.width, anchorPoint.y * size.height});
         view.bounds = {view.bounds.origin,size};
         */
        //apply frame
        renderer.frame  = {context.position, size};
        
        [parentRenderer addSubRenderer:renderer];
        
        //update mountedInfo
        _mountedInfo -> mountedContext = {nil,renderer,{context.position,size}};
        
        return {.hasChildren = YES, .childContext = context};
    } else {
        
        CGPoint origin = context.position;
        
        if (!renderer) {
            //如果当前node不能被光栅化，但是super node被光栅化了，那么当前node对应的view在添加到上级view的时候，origin需要进行转换
            VZFRenderer *superRenderer = parentRenderer;
            if (superRenderer) {
                while (superRenderer) {
                    origin = {origin.x + superRenderer.frame.origin.x, origin.y + superRenderer.frame.origin.y};
                    superRenderer = superRenderer.superRenderer;
                }
            }
        }
        
        
        //获取一个reuse view
        UIView* view = [context.viewManager viewForNode:self];
        
        //说明reusepool中有view
        if (view) {
            //不是当前的backingview
            if (view != _mountedInfo -> mountedView) {
                
                //释放当前mountedView绑定的node
                [view.node unmount];
                view.node = self;
                _mountedInfo -> mountedView = view;
                _mountedInfo -> mountedRenderer = renderer;
                [self didAquireBackingView:view];
            }
            else{
                VZFAssert(view.node == self, @"");
            }
                        
            if ([view conformsToProtocol:@protocol(VZFBackingViewProtocol)]) {
                id<VZFBackingViewProtocol> backingView = (id<VZFBackingViewProtocol>)view;
                [backingView setRenderer:renderer];
                renderer = [backingView renderer];
            }
            
            //计算公式:
            //position.x = frame.origin.x + anchorPoint.x * bounds.size.width；
            //position.y = frame.origin.y + anchorPoint.y * bounds.size.height；
            /*       const CGPoint anchorPoint = view.layer.anchorPoint;
             view.center = context.position + CGPoint({anchorPoint.x * size.width, anchorPoint.y * size.height});
             view.bounds = {view.bounds.origin,size};
             */
            //apply frame
            view.frame  = {origin, size};
            
            //apply attributes
            [view applyAttributes];
            
            //update mountedInfo
            _mountedInfo -> mountedContext = {view,renderer,{context.position,size}};
            
            return {.hasChildren = YES, .childContext = context.childContextForSubview(view)};
        }
        else{
            //这种情况对应于没有viewclass的node，例如compositeNode，他没有backingview，mount过程中使用的是view的是上一个view
            _mountedInfo -> mountedView = nil;
            _mountedInfo -> mountedRenderer = nil;
            _mountedInfo -> mountedContext = {context.viewManager.managedView, parentRenderer, {context.position,size}};
            
            return {.hasChildren = YES, .childContext = context};
        }
    }
}



-(void)unmount{
    
    //VZF_LOG_THREAD(@"unmount");
    
    if (_mountedInfo != nullptr)
    {
        [self  willUnmount];
        
        [self _recycleMountedView];

        _mountedInfo.reset();
        
        [self didUnmount];
    }

}

- (void)_recycleMountedView{
    
    UIView* view = _mountedInfo -> mountedView;
    
    if (view) {
        
        [self willReleaseBackingView:view];
        
        view.node = nil;
        _mountedInfo -> mountedView = nil;

    }
    
    VZFRenderer* renderer = _mountedInfo -> mountedRenderer;
    
    if (renderer) {
        renderer.node = nil;
        _mountedInfo -> mountedRenderer = nil;
        
    }

}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - life cycle

-(void)willMount{

    VZFAssertMainThread();
    
    switch (_state) {
        case VZFNodeStateUnmounted:
        {
            _state = VZFNodeStateMounting;
            break;
        }
        case VZFNodeStateMounted:
        {
            _state = VZFNodeStateRemounting;
            [self willRemount];
            break;
        }
        default:
        {
            VZFAssert(NO, @"State:[%@] Error: willmount -> '%@' ",[self class],VZFNodeStateName(_state));
            break;
        }
    }
}

- (void)willRemount{

    VZFAssertMainThread();

}

-(void)didMount{

    VZFAssertMainThread();
    
    switch (_state) {
        case VZFNodeStateMounting:
        {
            _state = VZFNodeStateMounted;
            break;
        }
        case VZFNodeStateRemounting:{
            _state = VZFNodeStateMounted;
            [self didRemount];
            break;
        }
        default:
        {
            VZFAssert(NO, @"State:[%@] Error: didmount -> '%@' ",[self class],VZFNodeStateName(_state));
            break;
        }
    }
    
    if (_specs.display) {
        [_specs.display invoke:self withCustomParam:_mountedInfo->mountedView];
    }
}

- (void)didRemount{

    VZFAssertMainThread();
}

- (void)willUnmount{

    VZFAssertMainThread();
    
    switch (_state) {
        case VZFNodeStateMounted:
        {
            _state = VZFNodeStateUnmounting;
            break;
        }
        default:
        {
            VZFAssert(NO, @"State:[%@] Error: will unmount -> '%@' ",[self class],VZFNodeStateName(_state));
            break;
        }
    }

    
}

- (void)didUnmount{

    VZFAssertMainThread();
    
    switch (_state) {
        case VZFNodeStateUnmounting:
            _state = VZFNodeStateUnmounted;
            break;
            
        default:{
            VZFAssert(NO, @"State:[%@] Error: did unmount -> '%@' ",[self class],VZFNodeStateName(_state));
            break;
        }
    }
}

- (void)willReleaseBackingView:(UIView *)view {

    VZFAssertMainThread();
    
    [view.layer removeAllAnimations];
}

- (void)didAquireBackingView:(UIView *)view {

    VZFAssertMainThread();
    
}


//////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSCopying
- (id)copyWithZone:(NSZone *)zone{
    //node is immutable object
    return self;
}


@end
