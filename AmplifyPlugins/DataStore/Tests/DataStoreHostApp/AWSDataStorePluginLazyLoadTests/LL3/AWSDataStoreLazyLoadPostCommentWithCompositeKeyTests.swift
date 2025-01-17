//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import Combine
import XCTest

@testable import Amplify
import AWSPluginsCore

final class AWSDataStoreLazyLoadPostCommentWithCompositeKeyTests: AWSDataStoreLazyLoadBaseTest {

    func testLazyLoad() async throws {
        await setup(withModels: PostCommentWithCompositeKeyModels())
        
        let post = Post(title: "title")
        let comment = Comment(content: "content", post: post)
        let savedPost = try await createAndWaitForSync(post)
        let savedComment = try await createAndWaitForSync(comment)
        try await assertComment(savedComment, canLazyLoad: savedPost)
        try await assertPost(savedPost, canLazyLoad: savedComment)
        let queriedComment = try await query(for: savedComment)
        try await assertComment(queriedComment, canLazyLoad: savedPost)
        let queriedPost = try await query(for: savedPost)
        try await assertPost(queriedPost, canLazyLoad: savedComment)
    }
    
    func assertComment(_ comment: Comment,
                       hasEagerLoaded post: Post) async throws {
        assertLazyReference(comment._post,
                        state: .loaded(model: post))
        
        guard let loadedPost = try await comment.post else {
            XCTFail("Failed to retrieve the post from the comment")
            return
        }
        XCTAssertEqual(loadedPost.id, post.id)
        
        // retrieve loaded model
        guard let loadedPost = try await comment.post else {
            XCTFail("Failed to retrieve the loaded post from the comment")
            return
        }
        XCTAssertEqual(loadedPost.id, post.id)
        
        try await assertPost(loadedPost, canLazyLoad: comment)
    }
    
    func assertComment(_ comment: Comment,
                       canLazyLoad post: Post) async throws {
        assertLazyReference(comment._post,
                        state: .notLoaded(identifiers: [
                            .init(name: Post.keys.id.stringValue, value: post.id),
                            .init(name: Post.keys.title.stringValue, value: post.title)
                        ]))
        guard let loadedPost = try await comment.post else {
            XCTFail("Failed to load the post from the comment")
            return
        }
        XCTAssertEqual(loadedPost.id, post.id)
        assertLazyReference(comment._post,
                        state: .loaded(model: post))
        try await assertPost(loadedPost, canLazyLoad: comment)
    }
    
    func assertPost(_ post: Post,
                    canLazyLoad comment: Comment) async throws {
        guard let comments = post.comments else {
            XCTFail("Missing comments on post")
            return
        }
        assertList(comments, state: .isNotLoaded(associatedIds: [post.identifier],
                                                 associatedFields: ["post"]))
        try await comments.fetch()
        assertList(comments, state: .isLoaded(count: 1))
        guard let comment = comments.first else {
            XCTFail("Missing lazy loaded comment from post")
            return
        }
        assertLazyReference(comment._post,
                        state: .notLoaded(identifiers: [
                            .init(name: Post.keys.id.stringValue, value: post.id),
                            .init(name: Post.keys.title.stringValue, value: post.title)
                        ]))
    }
    
    func testSaveWithoutPost() async throws {
        await setup(withModels: PostCommentWithCompositeKeyModels())
        let comment = Comment(content: "content")
        let savedComment = try await createAndWaitForSync(comment)
        var queriedComment = try await query(for: savedComment)
        assertLazyReference(queriedComment._post,
                        state: .notLoaded(identifiers: nil))
        let post = Post(title: "title")
        let savedPost = try await createAndWaitForSync(post)
        queriedComment.setPost(savedPost)
        let saveCommentWithPost = try await updateAndWaitForSync(queriedComment)
        let queriedComment2 = try await query(for: saveCommentWithPost)
        try await assertComment(queriedComment2, canLazyLoad: post)
    }
    
    func testUpdateFromQueriedComment() async throws {
        await setup(withModels: PostCommentWithCompositeKeyModels())
        let post = Post(title: "title")
        let comment = Comment(content: "content", post: post)
        let savedPost = try await createAndWaitForSync(post)
        let savedComment = try await createAndWaitForSync(comment)
        let queriedComment = try await query(for: savedComment)
        assertLazyReference(queriedComment._post,
                        state: .notLoaded(identifiers: [
                            .init(name: Post.keys.id.stringValue, value: post.id),
                            .init(name: Post.keys.title.stringValue, value: post.title)
                        ]))
        let savedQueriedComment = try await updateAndWaitForSync(queriedComment)
        let queriedComment2 = try await query(for: savedQueriedComment)
        try await assertComment(queriedComment2, canLazyLoad: savedPost)
    }
    
    func testUpdateToNewPost() async throws {
        await setup(withModels: PostCommentWithCompositeKeyModels())
        
        let post = Post(title: "title")
        let comment = Comment(content: "content", post: post)
        _ = try await createAndWaitForSync(post)
        let savedComment = try await createAndWaitForSync(comment)
        var queriedComment = try await query(for: savedComment)
        assertLazyReference(queriedComment._post,
                        state: .notLoaded(identifiers: [
                            .init(name: Post.keys.id.stringValue, value: post.id),
                            .init(name: Post.keys.title.stringValue, value: post.title)
                        ]))
        
        let newPost = Post(title: "title")
        _ = try await createAndWaitForSync(newPost)
        queriedComment.setPost(newPost)
        let saveCommentWithNewPost = try await updateAndWaitForSync(queriedComment)
        let queriedComment2 = try await query(for: saveCommentWithNewPost)
        try await assertComment(queriedComment2, canLazyLoad: newPost)
    }
    
    func testUpdateRemovePost() async throws {
        await setup(withModels: PostCommentWithCompositeKeyModels())
        
        let post = Post(title: "title")
        let comment = Comment(content: "content", post: post)
        _ = try await createAndWaitForSync(post)
        let savedComment = try await createAndWaitForSync(comment)
        var queriedComment = try await query(for: savedComment)
        assertLazyReference(queriedComment._post,
                        state: .notLoaded(identifiers: [
                            .init(name: Post.keys.id.stringValue, value: post.id),
                            .init(name: Post.keys.title.stringValue, value: post.title)
                        ]))
        
        queriedComment.setPost(nil)
        let saveCommentRemovePost = try await updateAndWaitForSync(queriedComment)
        let queriedCommentNoPost = try await query(for: saveCommentRemovePost)
        assertLazyReference(queriedCommentNoPost._post,
                        state: .notLoaded(identifiers: nil))
    }
    
    func testDelete() async throws {
        await setup(withModels: PostCommentWithCompositeKeyModels())
        
        let post = Post(title: "title")
        let comment = Comment(content: "content", post: post)
        let savedPost = try await createAndWaitForSync(post)
        let savedComment = try await createAndWaitForSync(comment)
        try await deleteAndWaitForSync(savedPost)
        try await assertModelDoesNotExist(savedComment)
        try await assertModelDoesNotExist(savedPost)
    }
    
    func testObservePost() async throws {
        await setup(withModels: PostCommentWithCompositeKeyModels())
        try await startAndWaitForReady()
        let post = Post(title: "title")
        let comment = Comment(content: "content", post: post)
        let mutationEventReceived = asyncExpectation(description: "Received mutation event")
        let mutationEvents = Amplify.DataStore.observe(Post.self)
        Task {
            for try await mutationEvent in mutationEvents {
                if let version = mutationEvent.version,
                   version == 1,
                   let receivedPost = try? mutationEvent.decodeModel(as: Post.self),
                   receivedPost.id == post.id {
                        
                    try await createAndWaitForSync(comment)
                    guard let comments = receivedPost.comments else {
                        XCTFail("Lazy List does not exist")
                        return
                    }
                    do {
                        try await comments.fetch()
                    } catch {
                        XCTFail("Failed to lazy load comments \(error)")
                    }
                    XCTAssertEqual(comments.count, 1)
                    
                    await mutationEventReceived.fulfill()
                }
            }
        }
        
        let createRequest = GraphQLRequest<MutationSyncResult>.createMutation(of: post, modelSchema: Post.schema)
        do {
            _ = try await Amplify.API.mutate(request: createRequest)
        } catch {
            XCTFail("Failed to send mutation request \(error)")
        }
        
        await waitForExpectations([mutationEventReceived], timeout: 60)
        mutationEvents.cancel()
    }
    
    func testObserveComment() async throws {
        await setup(withModels: PostCommentWithCompositeKeyModels())
        try await startAndWaitForReady()
        let post = Post(title: "title")
        let savedPost = try await createAndWaitForSync(post)
        let comment = Comment(content: "content", post: post)
        let mutationEventReceived = asyncExpectation(description: "Received mutation event")
        let mutationEvents = Amplify.DataStore.observe(Comment.self)
        Task {
            for try await mutationEvent in mutationEvents {
                if let version = mutationEvent.version,
                   version == 1,
                   let receivedComment = try? mutationEvent.decodeModel(as: Comment.self),
                   receivedComment.id == comment.id {
                    try await assertComment(receivedComment, canLazyLoad: savedPost)
                    await mutationEventReceived.fulfill()
                }
            }
        }
        
        let createRequest = GraphQLRequest<MutationSyncResult>.createMutation(of: comment, modelSchema: Comment.schema)
        do {
            _ = try await Amplify.API.mutate(request: createRequest)
        } catch {
            XCTFail("Failed to send mutation request \(error)")
        }
        
        await waitForExpectations([mutationEventReceived], timeout: 60)
        mutationEvents.cancel()
    }
    
    func testObserveQueryPost() async throws {
        await setup(withModels: PostCommentWithCompositeKeyModels())
        try await startAndWaitForReady()
        let post = Post(title: "title")
        let comment = Comment(content: "content", post: post)
        let snapshotReceived = asyncExpectation(description: "Received query snapshot")
        let querySnapshots = Amplify.DataStore.observeQuery(for: Post.self, where: Post.keys.id == post.id)
        Task {
            for try await querySnapshot in querySnapshots {
                if let receivedPost = querySnapshot.items.first {
                    try await createAndWaitForSync(comment)
                    guard let comments = receivedPost.comments else {
                        XCTFail("Lazy List does not exist")
                        return
                    }
                    do {
                        try await comments.fetch()
                    } catch {
                        XCTFail("Failed to lazy load comments \(error)")
                    }
                    XCTAssertEqual(comments.count, 1)
                    
                    await snapshotReceived.fulfill()
                }
            }
        }
        
        let createRequest = GraphQLRequest<MutationSyncResult>.createMutation(of: post, modelSchema: Post.schema)
        do {
            _ = try await Amplify.API.mutate(request: createRequest)
        } catch {
            XCTFail("Failed to send mutation request \(error)")
        }
        
        await waitForExpectations([snapshotReceived], timeout: 60)
        querySnapshots.cancel()
    }
    
    func testObserveQueryComment() async throws {
        await setup(withModels: PostCommentWithCompositeKeyModels())
        try await startAndWaitForReady()
        
        let post = Post(title: "title")
        let savedPost = try await createAndWaitForSync(post)
        let comment = Comment(content: "content", post: post)
        let snapshotReceived = asyncExpectation(description: "Received query snapshot")
        let querySnapshots = Amplify.DataStore.observeQuery(for: Comment.self, where: Comment.keys.id == comment.id)
        Task {
            for try await querySnapshot in querySnapshots {
                if let receivedComment = querySnapshot.items.first {
                    try await assertComment(receivedComment, canLazyLoad: savedPost)
                    await snapshotReceived.fulfill()
                }
            }
        }
        
        let createRequest = GraphQLRequest<MutationSyncResult>.createMutation(of: comment, modelSchema: Comment.schema)
        do {
            _ = try await Amplify.API.mutate(request: createRequest)
        } catch {
            XCTFail("Failed to send mutation request \(error)")
        }
        
        await waitForExpectations([snapshotReceived], timeout: 60)
        querySnapshots.cancel()
    }
}

extension AWSDataStoreLazyLoadPostCommentWithCompositeKeyTests {
    typealias Post = PostWithCompositeKey
    typealias Comment = CommentWithCompositeKey
    
    struct PostCommentWithCompositeKeyModels: AmplifyModelRegistration {
        public let version: String = "version"
        func registerModels(registry: ModelRegistry.Type) {
            ModelRegistry.register(modelType: PostWithCompositeKey.self)
            ModelRegistry.register(modelType: CommentWithCompositeKey.self)
        }
    }
}
