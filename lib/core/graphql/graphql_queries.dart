const kLoginMutation = r'''
mutation Login($userId: String!, $password: String!) {
  login(userId: $userId, password: $password) {
    token
    role
    loungeId
  }
}
''';

const kOrdersQuery = r'''
query Orders($limit: Int) {
  orders(limit: $limit) {
    id
    userId
    loungeId
    flavor
    comment
    phone
    arrivalAt
    status
    createdAt
  }
}
''';

const kUpdateOrderStatusMutation = r'''
mutation UpdateOrderStatus($orderId: String!, $status: String!) {
  updateOrderStatus(orderId: $orderId, status: $status) {
    id
    status
  }
}
''';

const kDeleteOrderMutation = r'''
mutation DeleteOrder($orderId: String!) {
  deleteOrder(orderId: $orderId)
}
''';

const kLoungesQuery = r'''
query Lounges {
  lounges {
    id
    name
    description
    schedule
    phone
    rating
    shortAddress
    latitude
    longitude
    ownerUserId
    staff {
      id
      userId
      firstName
      lastName
      role
    }
  }
}
''';

const kCreateLoungeMutation = r'''
mutation CreateLounge(
  $name: String!
  $description: String
  $schedule: String
  $phone: String
  $shortAddress: String
  $latitude: Float
  $longitude: Float
) {
  createLounge(
    name: $name
    description: $description
    schedule: $schedule
    phone: $phone
    shortAddress: $shortAddress
    latitude: $latitude
    longitude: $longitude
  ) {
    id
    name
  }
}
''';

const kUpdateLoungeMutation = r'''
mutation UpdateLounge(
  $loungeId: String!
  $name: String!
  $description: String
  $schedule: String
  $phone: String
  $shortAddress: String
  $latitude: Float
  $longitude: Float
) {
  updateLounge(
    loungeId: $loungeId
    name: $name
    description: $description
    schedule: $schedule
    phone: $phone
    shortAddress: $shortAddress
    latitude: $latitude
    longitude: $longitude
  ) {
    id
    name
  }
}
''';

const kDeleteLoungeMutation = r'''
mutation DeleteLounge($loungeId: String!) {
  deleteLounge(loungeId: $loungeId)
}
''';

const kSetLoungeOwnerMutation = r'''
mutation SetLoungeOwner($loungeId: String!, $ownerUserId: String!) {
  setLoungeOwner(loungeId: $loungeId, ownerUserId: $ownerUserId) {
    id
  }
}
''';

const kStaffQuery = r'''
query Staff {
  staff {
    id
    userId
    loungeId
    firstName
    lastName
    role
    rating
  }
}
''';

const kCreateStaffMutation = r'''
mutation CreateStaff(
  $userId: String!
  $password: String!
  $loungeId: String!
  $firstName: String
  $lastName: String
  $role: String!
) {
  createStaff(
    userId: $userId
    password: $password
    loungeId: $loungeId
    firstName: $firstName
    lastName: $lastName
    role: $role
  ) {
    id
    userId
    role
    loungeId
  }
}
''';

const kCreateAdminMutation = r'''
mutation CreateAdmin(
  $userId: String!
  $password: String!
  $firstName: String
  $lastName: String
) {
  createAdmin(
    userId: $userId
    password: $password
    firstName: $firstName
    lastName: $lastName
  ) {
    id
    userId
    role
  }
}
''';

const kUpdateStaffMutation = r'''
mutation UpdateStaff(
  $staffId: String!
  $firstName: String
  $lastName: String
  $role: String
  $loungeId: String
  $password: String
) {
  updateStaff(
    staffId: $staffId
    firstName: $firstName
    lastName: $lastName
    role: $role
    loungeId: $loungeId
    password: $password
  ) {
    id
  }
}
''';

const kDeleteStaffMutation = r'''
mutation DeleteStaff($staffId: String!) {
  deleteStaff(staffId: $staffId)
}
''';

const kMessagesQuery = r'''
query Messages($orderId: String!) {
  messages(orderId: $orderId) {
    id
    senderId
    senderRole
    text
    createdAt
  }
}
''';

const kSendMessageMutation = r'''
mutation SendMessage($orderId: String!, $text: String!) {
  sendMessage(orderId: $orderId, text: $text) {
    id
    createdAt
  }
}
''';

const kOrderStatusChangedSubscription = r'''
subscription OrderStatusChanged {
  orderStatusChanged {
    id
    status
  }
}
''';

const kNewMessageSubscription = r'''
subscription NewMessage {
  newMessage {
    orderId
    senderId
    senderRole
    text
  }
}
''';
